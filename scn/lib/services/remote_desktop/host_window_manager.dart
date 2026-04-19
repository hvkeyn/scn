import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'package:scn/utils/logger.dart';

/// Управление главным окном SCN на хост-машине во время активной сессии RD.
///
/// Проблема: пока хост стримит экран, окно SCN на хосте находится поверх
/// других окон. Когда viewer "кликает свернуть/закрыть" в координатах,
/// которые на хосте попадают НА title-bar SCN, клик уходит в SCN — окно
/// сворачивается, Flutter Windows lifecycle переходит в `paused`, и
/// `RTCDataChannel.onMessage` перестаёт обрабатываться. В лог хоста это
/// видно как "пропал" mouseUp на 20+ секунд (события скапливаются и
/// выдаются пачкой когда юзер раз-сворачивает SCN).
///
/// Решение: на время сессии съёживаем окно SCN до 1×1 в углу экрана.
///   - Не minimized → Flutter остаётся в `resumed`, DataChannel живой.
///   - Не получает кликов мыши (попасть в 1 пиксель практически невозможно).
///   - По завершении сессии — восстанавливаем оригинальный размер/позицию.
class HostWindowManager {
  static int _activeSessions = 0;
  static _SavedRect? _savedRect;
  static int _savedHwnd = 0;

  static void onSessionStarted() {
    _activeSessions++;
    if (_activeSessions == 1) {
      _shrinkMainWindow();
    }
  }

  static void onSessionEnded() {
    if (_activeSessions == 0) return;
    _activeSessions--;
    if (_activeSessions == 0) {
      _restoreMainWindow();
    }
  }

  static void _shrinkMainWindow() {
    if (!Platform.isWindows) return;
    try {
      final pid = GetCurrentProcessId();
      final hwnd = _findMainWindowOfProcess(pid);
      if (hwnd == 0) {
        AppLogger.log('HostWindowManager: main window not found');
        return;
      }
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
      const swpNoZorder = 0x0004;
      const swpNoActivate = 0x0010;
      SetWindowPos(hwnd, 0, 0, 0, 1, 1, swpNoZorder | swpNoActivate);
      AppLogger.log(
          'HostWindowManager: shrunk SCN window hwnd=$hwnd to 1x1 '
          '(saved rect=$_savedRect)');
    } catch (e, st) {
      AppLogger.log('HostWindowManager: shrink failed: $e\n$st');
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

  static int _findMainWindowOfProcess(int pid) {
    int found = 0;
    final pidPtr = calloc<Uint32>();
    try {
      final cb = NativeCallable<EnumWindowsProc>.isolateLocal(
        (int hwnd, int lParam) {
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
