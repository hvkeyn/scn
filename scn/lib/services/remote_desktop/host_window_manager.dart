import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'package:scn/utils/logger.dart';

/// Управление главным окном SCN на хост-машине во время активной сессии RD.
///
/// Проблема: пока хост стримит экран, окно SCN на хосте находится поверх
/// других окон. Когда viewer "кликает свернуть/закрыть" в координатах,
/// которые на хосте попадают НА title-bar SCN или его debug-консоль, клик
/// уходит в SCN, активирует/сворачивает его, Flutter Windows lifecycle
/// переходит в `paused`/`inactive`, и `RTCDataChannel.onMessage` перестаёт
/// обрабатываться (события скапливаются и выдаются пачкой когда юзер
/// раз-сворачивает SCN).
///
/// Решение:
///   1. На время сессии **переносим окно SCN за пределы экрана**
///      (-32000,-32000) и сжимаем до 1×1. Окно не minimized → Flutter
///      остаётся `resumed`. Гарантированно не получает кликов мыши, т.к.
///      его HWND вообще нет в видимой части экрана.
///   2. Скрываем debug-консоль Flutter (только debug-сборка): её title-bar
///      виден на экране и по нему тоже легко кликнуть.
///   3. По завершении ВСЕХ сессий — восстанавливаем оригинальный rect и
///      возвращаем консоль.
class HostWindowManager {
  static int _activeSessions = 0;
  static _SavedRect? _savedRect;
  static int _savedHwnd = 0;
  static int _savedConsoleHwnd = 0;

  static bool get hasActiveSessions => _activeSessions > 0;

  // Координаты "виртуального небытия" в Windows: окно с такими x/y
  // сохраняет свой HWND, не minimized, но не виден пользователю и не
  // принимает hit-test'ов от мыши.
  static const int _hiddenX = -32000;
  static const int _hiddenY = -32000;

  static void onSessionStarted() {
    _activeSessions++;
    if (_activeSessions == 1) {
      _hideMainWindow();
      _hideConsoleWindow();
    }
  }

  static void onSessionEnded() {
    if (_activeSessions == 0) return;
    _activeSessions--;
    if (_activeSessions == 0) {
      _restoreMainWindow();
      _restoreConsoleWindow();
    }
  }

  static void keepHiddenIfNeeded() {
    if (_activeSessions <= 0) return;
    _hideMainWindow();
    _hideConsoleWindow();
  }

  static void _hideMainWindow() {
    if (!Platform.isWindows) return;
    try {
      final pid = GetCurrentProcessId();
      final hwnd = _findMainWindowOfProcess(pid);
      if (hwnd == 0) {
        AppLogger.log('HostWindowManager: main window not found');
        return;
      }
      if (_savedHwnd == 0) {
        final rectPtr = calloc<RECT>();
        try {
          if (GetWindowRect(hwnd, rectPtr) != 0) {
            _savedRect = _SavedRect(
              left: rectPtr.ref.left,
              top: rectPtr.ref.top,
              width: rectPtr.ref.right - rectPtr.ref.left,
              height: rectPtr.ref.bottom - rectPtr.ref.top,
            );
            _savedHwnd = hwnd;
          }
        } finally {
          calloc.free(rectPtr);
        }
      } else if (_savedHwnd != hwnd) {
        AppLogger.log(
          'HostWindowManager: keeping saved hwnd=$_savedHwnd, current hwnd=$hwnd',
        );
      }
      const swpNoZorder = 0x0004;
      const swpNoActivate = 0x0010;
      SetWindowPos(
          hwnd, 0, _hiddenX, _hiddenY, 1, 1, swpNoZorder | swpNoActivate);
      AppLogger.log('HostWindowManager: moved SCN window hwnd=$hwnd off-screen '
          '($_hiddenX,$_hiddenY 1x1), saved rect=$_savedRect');
    } catch (e, st) {
      AppLogger.log('HostWindowManager: hide failed: $e\n$st');
    }
  }

  static void _restoreMainWindow() {
    if (!Platform.isWindows) return;
    final saved = _savedRect;
    final hwnd = _savedHwnd;
    if (saved == null || hwnd == 0) return;
    try {
      const swpNoZorder = 0x0004;
      const swpNoActivate = 0x0010;
      SetWindowPos(hwnd, 0, saved.left, saved.top, saved.width, saved.height,
          swpNoZorder | swpNoActivate);
      AppLogger.log(
          'HostWindowManager: restored SCN window hwnd=$hwnd to $saved');
    } catch (e) {
      AppLogger.log('HostWindowManager: restore failed: $e');
    } finally {
      _savedRect = null;
      _savedHwnd = 0;
    }
  }

  /// Скрывает консольное окно (debug-сборка Flutter Windows). В release
  /// сборке GetConsoleWindow вернёт 0 — no-op.
  static void _hideConsoleWindow() {
    if (!Platform.isWindows) return;
    try {
      final hConsole = GetConsoleWindow();
      if (hConsole == 0) return;
      _savedConsoleHwnd = hConsole;
      ShowWindow(hConsole, SW_HIDE);
      AppLogger.log('HostWindowManager: hidden console hwnd=$hConsole');
    } catch (e) {
      AppLogger.log('HostWindowManager: hide console failed: $e');
    }
  }

  static void _restoreConsoleWindow() {
    if (!Platform.isWindows) return;
    if (_savedConsoleHwnd == 0) return;
    try {
      ShowWindow(_savedConsoleHwnd, SW_SHOW);
      AppLogger.log(
          'HostWindowManager: restored console hwnd=$_savedConsoleHwnd');
    } catch (e) {
      AppLogger.log('HostWindowManager: restore console failed: $e');
    } finally {
      _savedConsoleHwnd = 0;
    }
  }

  static int _findMainWindowOfProcess(int pid) {
    int found = 0;
    final consoleHwnd = Platform.isWindows ? GetConsoleWindow() : 0;
    final pidPtr = calloc<Uint32>();
    try {
      final cb = NativeCallable<EnumWindowsProc>.isolateLocal(
        (int hwnd, int lParam) {
          if (hwnd == consoleHwnd) {
            return TRUE;
          }
          GetWindowThreadProcessId(hwnd, pidPtr);
          if (pidPtr.value == pid && IsWindowVisible(hwnd) != 0) {
            if (GetWindow(hwnd, GW_OWNER) == 0) {
              found = hwnd;
              return FALSE;
            }
          }
          return TRUE;
        },
        exceptionalReturn: TRUE,
      );
      try {
        EnumWindows(cb.nativeFunction, 0);
      } finally {
        cb.close();
      }
    } finally {
      calloc.free(pidPtr);
    }
    return found;
  }
}

class _SavedRect {
  final int left;
  final int top;
  final int width;
  final int height;
  const _SavedRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  @override
  String toString() => '($left,$top ${width}x$height)';
}
