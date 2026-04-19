import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'package:scn/utils/logger.dart';

/// Управление окном самого SCN на хост-машине во время активной сессии
/// удалённого рабочего стола.
///
/// Зачем: когда хост стримит экран и принимает клики/моусмув от viewer'а,
/// инжектируемые SendInput-события идут в **то окно, которое сейчас под
/// курсором на хосте**. Если SCN-окно само находится на переднем плане
/// (или хотя бы перекрывает целевую область), клик "Свернуть программу"
/// из удалённого стола попадёт В САМОЕ SCN, а не в нужное приложение.
/// Симптомы в точности такие, как описывал юзер: картинка идёт, но мышь
/// "теряется" — фактически она кликнула по UI самого SCN.
///
/// Решение: на время активной сессии минимизируем главное окно SCN
/// (на Windows — через win32 ShowWindow). По завершении не восстанавливаем
/// автоматически: пользователь сам решит, нужно ли разворачивать.
class HostWindowManager {
  static int _activeSessions = 0;
  static bool _wasMinimized = false;

  static void onSessionStarted() {
    _activeSessions++;
    if (_activeSessions == 1) {
      _wasMinimized = _minimizeMainWindow();
      AppLogger.log(
          'HostWindowManager: session started, minimized=$_wasMinimized '
          'active=$_activeSessions');
    } else {
      AppLogger.log(
          'HostWindowManager: another session started (active=$_activeSessions)');
    }
  }

  static void onSessionEnded() {
    if (_activeSessions == 0) return;
    _activeSessions--;
    AppLogger.log(
        'HostWindowManager: session ended (active=$_activeSessions)');
    if (_activeSessions == 0) {
      _wasMinimized = false;
    }
  }

  static bool _minimizeMainWindow() {
    if (!Platform.isWindows) return false;
    try {
      final pid = GetCurrentProcessId();
      final hwnd = _findMainWindowOfProcess(pid);
      if (hwnd == 0) {
        AppLogger.log('HostWindowManager: main window not found');
        return false;
      }
      // SW_MINIMIZE — свернуть, оставив фокус на следующем окне в Z-order.
      // SW_FORCEMINIMIZE надёжнее, если окно "висит", но требует прав;
      // для своего же процесса SW_MINIMIZE достаточно.
      ShowWindow(hwnd, SW_MINIMIZE);
      return true;
    } catch (e, st) {
      AppLogger.log('HostWindowManager: minimize failed: $e\n$st');
      return false;
    }
  }

  /// Перебирает топ-уровневые окна и возвращает HWND того, что принадлежит
  /// нашему процессу и видимо. У Flutter-приложения обычно одно главное
  /// окно — берём первое подходящее.
  static int _findMainWindowOfProcess(int pid) {
    int found = 0;
    final pidPtr = calloc<Uint32>();
    try {
      final cb = NativeCallable<EnumWindowsProc>.isolateLocal(
        (int hwnd, int lParam) {
          GetWindowThreadProcessId(hwnd, pidPtr);
          if (pidPtr.value == pid && IsWindowVisible(hwnd) != 0) {
            // Игнорируем child/owned окна — нам нужно top-level.
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
