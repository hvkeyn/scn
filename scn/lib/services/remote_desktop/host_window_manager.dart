import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:scn/utils/logger.dart';
import 'package:win32/win32.dart';

/// Прячет окно SCN во время RD-сессии (клики не бьют в Flutter),
/// но позволяет локально вернуть его через taskbar / tray.
class HostWindowManager {
  HostWindowManager._();

  static int _activeSessions = 0;
  static bool get hasActiveSessions => _activeSessions > 0;

  static int? _savedX;
  static int? _savedY;
  static int? _savedWidth;
  static int? _savedHeight;
  static int? _savedShowCmd;
  static int? _hwnd;
  static bool _hidden = false;
  static bool _userRestored = false;

  static int? _savedConsoleX;
  static int? _savedConsoleY;
  static int? _savedConsoleWidth;
  static int? _savedConsoleHeight;
  static int? _savedConsoleShowCmd;
  static int? _consoleHwnd;
  static bool _consoleHidden = false;

  static Timer? _activationWatch;

  static void onSessionStarted() {
    _activeSessions++;
    AppLogger.log(
        'HostWindowManager: session started (active=$_activeSessions)');
    if (_activeSessions == 1) {
      _userRestored = false;
      _hideMainWindow();
      if (kDebugMode) _hideConsoleWindow();
    }
  }

  static void onSessionEnded() {
    if (_activeSessions > 0) _activeSessions--;
    AppLogger.log(
        'HostWindowManager: session ended (active=$_activeSessions)');
    if (_activeSessions == 0) {
      _stopActivationWatch();
      _userRestored = false;
      _restoreMainWindow();
      if (kDebugMode) _restoreConsoleWindow();
    }
  }

  /// Пользователь нажал SCN в taskbar/tray — показать окно поверх.
  static void restoreForUser() {
    if (!Platform.isWindows || _activeSessions <= 0) return;
    _userRestored = true;
    _stopActivationWatch();
    final hwnd = _findMainHwnd();
    if (hwnd == 0) return;
    _hwnd = hwnd;

    if (_hidden &&
        _savedX != null &&
        _savedY != null &&
        _savedWidth != null &&
        _savedHeight != null) {
      SetWindowPos(
        hwnd,
        HWND_TOP,
        _savedX!,
        _savedY!,
        _savedWidth!,
        _savedHeight!,
        SWP_NOACTIVATE,
      );
      _hidden = false;
    }

    final showCmd = _savedShowCmd == SW_SHOWMINIMIZED
        ? SW_RESTORE
        : (_savedShowCmd ?? SW_RESTORE);
    ShowWindow(hwnd, showCmd);
    ShowWindow(hwnd, SW_SHOW);
    BringWindowToTop(hwnd);
    SetForegroundWindow(hwnd);
    SetActiveWindow(hwnd);
    SetFocus(hwnd);
    AppLogger.log('HostWindowManager: restored for user (hwnd=$hwnd)');
  }

  /// Пока сессия активна и пользователь не открыл SCN — держать окно скрытым.
  static void keepHiddenIfNeeded() {
    if (_activeSessions > 0 && !_userRestored) {
      _hideMainWindow();
      if (kDebugMode) _hideConsoleWindow();
    }
  }

  static void _hideMainWindow() {
    if (!Platform.isWindows || _hidden || _userRestored) return;
    try {
      final hwnd = _findMainHwnd();
      if (hwnd == 0) {
        AppLogger.log('HostWindowManager: main hwnd not found');
        return;
      }
      _hwnd = hwnd;

      final wp = calloc<WINDOWPLACEMENT>();
      try {
        wp.ref.length = sizeOf<WINDOWPLACEMENT>();
        if (GetWindowPlacement(hwnd, wp) != 0) {
          _savedShowCmd = wp.ref.showCmd;
          _savedX = wp.ref.rcNormalPosition.left;
          _savedY = wp.ref.rcNormalPosition.top;
          _savedWidth =
              wp.ref.rcNormalPosition.right - wp.ref.rcNormalPosition.left;
          _savedHeight =
              wp.ref.rcNormalPosition.bottom - wp.ref.rcNormalPosition.top;
        }
      } finally {
        calloc.free(wp);
      }

      SetWindowPos(
        hwnd,
        HWND_BOTTOM,
        -32000,
        -32000,
        1,
        1,
        SWP_NOACTIVATE | SWP_NOSENDCHANGING,
      );
      _hidden = true;
      AppLogger.log(
          'HostWindowManager: hidden hwnd=$hwnd '
          '(was ${_savedWidth}x$_savedHeight @ $_savedX,$_savedY)');
      _startActivationWatch();
    } catch (e) {
      AppLogger.log('HostWindowManager: hide failed: $e');
    }
  }

  static void _restoreMainWindow() {
    if (!Platform.isWindows || !_hidden) return;
    try {
      final hwnd = _hwnd ?? _findMainHwnd();
      if (hwnd == 0) return;

      if (_savedX != null &&
          _savedY != null &&
          _savedWidth != null &&
          _savedHeight != null) {
        SetWindowPos(
          hwnd,
          HWND_TOP,
          _savedX!,
          _savedY!,
          _savedWidth!,
          _savedHeight!,
          SWP_NOACTIVATE,
        );
      }

      final showCmd = _savedShowCmd ?? SW_RESTORE;
      ShowWindow(hwnd, showCmd == SW_SHOWMINIMIZED ? SW_RESTORE : showCmd);
      _hidden = false;
      AppLogger.log('HostWindowManager: restored hwnd=$hwnd');
    } catch (e) {
      AppLogger.log('HostWindowManager: restore failed: $e');
    }
  }

  static void _startActivationWatch() {
    _activationWatch?.cancel();
    _activationWatch =
        Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (_activeSessions <= 0 || _userRestored || !_hidden) {
        _stopActivationWatch();
        return;
      }
      final hwnd = _hwnd ?? 0;
      if (hwnd == 0) return;
      if (GetForegroundWindow() == hwnd) {
        AppLogger.log(
            'HostWindowManager: taskbar activation detected → restore');
        restoreForUser();
      }
    });
  }

  static void _stopActivationWatch() {
    _activationWatch?.cancel();
    _activationWatch = null;
  }

  static int _findMainHwnd() {
    final pid = GetCurrentProcessId();
    final result = calloc<IntPtr>();
    final pidPtr = calloc<Uint32>()..value = pid;
    try {
      final callback = NativeCallable<EnumWindowsProc>.isolateLocal(
        (int hwnd, int lParam) {
          final windowPid = calloc<Uint32>();
          try {
            GetWindowThreadProcessId(hwnd, windowPid);
            if (windowPid.value != pid) return TRUE;
            if (GetWindow(hwnd, GW_OWNER) != 0) return TRUE;
            if (IsWindowVisible(hwnd) == 0 && !_hidden) return TRUE;

            final cls = wsalloc(256);
            try {
              GetClassName(hwnd, cls, 256);
              final className = cls.toDartString();
              if (className.contains('Flutter') ||
                  className.contains('FLUTTER') ||
                  className == 'FLUTTERVIEW' ||
                  className.contains('Win32Window')) {
                result.value = hwnd;
                return FALSE;
              }
            } finally {
              free(cls);
            }

            final title = wsalloc(256);
            try {
              GetWindowText(hwnd, title, 256);
              final t = title.toDartString().toLowerCase();
              if (t.contains('scn') || t.contains('localsend')) {
                result.value = hwnd;
                return FALSE;
              }
            } finally {
              free(title);
            }
            return TRUE;
          } finally {
            calloc.free(windowPid);
          }
        },
        exceptionalReturn: 0,
      );
      try {
        EnumWindows(callback.nativeFunction, pidPtr.address);
      } finally {
        callback.close();
      }
      return result.value;
    } finally {
      calloc.free(result);
      calloc.free(pidPtr);
    }
  }

  static void _hideConsoleWindow() {
    if (!Platform.isWindows || _consoleHidden) return;
    try {
      final hwnd = GetConsoleWindow();
      if (hwnd == 0) return;
      _consoleHwnd = hwnd;

      final wp = calloc<WINDOWPLACEMENT>();
      try {
        wp.ref.length = sizeOf<WINDOWPLACEMENT>();
        if (GetWindowPlacement(hwnd, wp) != 0) {
          _savedConsoleShowCmd = wp.ref.showCmd;
          _savedConsoleX = wp.ref.rcNormalPosition.left;
          _savedConsoleY = wp.ref.rcNormalPosition.top;
          _savedConsoleWidth =
              wp.ref.rcNormalPosition.right - wp.ref.rcNormalPosition.left;
          _savedConsoleHeight =
              wp.ref.rcNormalPosition.bottom - wp.ref.rcNormalPosition.top;
        }
      } finally {
        calloc.free(wp);
      }

      SetWindowPos(
        hwnd,
        HWND_BOTTOM,
        -32000,
        -32000,
        1,
        1,
        SWP_NOACTIVATE | SWP_NOSENDCHANGING,
      );
      _consoleHidden = true;
      AppLogger.log('HostWindowManager: console hidden hwnd=$hwnd');
    } catch (e) {
      AppLogger.log('HostWindowManager: console hide failed: $e');
    }
  }

  static void _restoreConsoleWindow() {
    if (!Platform.isWindows || !_consoleHidden) return;
    try {
      final hwnd = _consoleHwnd ?? GetConsoleWindow();
      if (hwnd == 0) return;

      if (_savedConsoleX != null &&
          _savedConsoleY != null &&
          _savedConsoleWidth != null &&
          _savedConsoleHeight != null) {
        SetWindowPos(
          hwnd,
          HWND_TOP,
          _savedConsoleX!,
          _savedConsoleY!,
          _savedConsoleWidth!,
          _savedConsoleHeight!,
          SWP_NOACTIVATE,
        );
      }

      final showCmd = _savedConsoleShowCmd ?? SW_RESTORE;
      ShowWindow(
          hwnd, showCmd == SW_SHOWMINIMIZED ? SW_RESTORE : showCmd);
      _consoleHidden = false;
      AppLogger.log('HostWindowManager: console restored hwnd=$hwnd');
    } catch (e) {
      AppLogger.log('HostWindowManager: console restore failed: $e');
    }
  }
}
