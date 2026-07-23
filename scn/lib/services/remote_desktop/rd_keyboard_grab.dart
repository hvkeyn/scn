import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'package:scn/utils/logger.dart';

/// Low-level keyboard hook so Win+Arrow / Win+… go to the remote session
/// instead of the local Windows shell (snap, etc.).
class RdKeyboardGrab {
  RdKeyboardGrab._();

  static bool get isSupported => Platform.isWindows;
  static bool get isActive => _hook != 0;

  static int _hook = 0;
  static NativeCallable<IntPtr Function(Int32, IntPtr, IntPtr)>? _callable;
  static void Function(int vk, bool down)? _onKey;

  static final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');
  static final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

  static final _setWindowsHookEx = _user32.lookupFunction<
      IntPtr Function(Int32, Pointer, IntPtr, Uint32),
      int Function(int, Pointer, int, int)>('SetWindowsHookExW');
  static final _unhookWindowsHookEx =
      _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
          'UnhookWindowsHookEx');
  static final _callNextHookEx = _user32.lookupFunction<
      IntPtr Function(IntPtr, Int32, IntPtr, IntPtr),
      int Function(int, int, int, int)>('CallNextHookEx');
  static final _getModuleHandle = _kernel32.lookupFunction<
      IntPtr Function(Pointer<Utf16>),
      int Function(Pointer<Utf16>)>('GetModuleHandleW');

  /// Start eating local OS hotkeys and forwarding VK codes.
  static void start(void Function(int vk, bool down) onKey) {
    if (!isSupported) return;
    stop();
    _onKey = onKey;
    try {
      _callable =
          NativeCallable<IntPtr Function(Int32, IntPtr, IntPtr)>.isolateLocal(
              _hookProc,
              exceptionalReturn: 0);
      final hMod = _getModuleHandle(nullptr);
      _hook = _setWindowsHookEx(
        13, // WH_KEYBOARD_LL
        _callable!.nativeFunction,
        hMod,
        0,
      );
      if (_hook == 0) {
        AppLogger.log('RdKeyboardGrab: SetWindowsHookEx failed');
        _callable?.close();
        _callable = null;
        _onKey = null;
      } else {
        AppLogger.log('RdKeyboardGrab: started');
      }
    } catch (e) {
      AppLogger.log('RdKeyboardGrab: start failed: $e');
      stop();
    }
  }

  static void stop() {
    if (_hook != 0) {
      _unhookWindowsHookEx(_hook);
      _hook = 0;
      AppLogger.log('RdKeyboardGrab: stopped');
    }
    _callable?.close();
    _callable = null;
    _onKey = null;
  }

  static int _hookProc(int nCode, int wParam, int lParam) {
    if (nCode == 0 /* HC_ACTION */ && _onKey != null && lParam != 0) {
      final vk = Pointer<Uint32>.fromAddress(lParam).value;
      const wmKeyDown = 0x0100;
      const wmKeyUp = 0x0101;
      const wmSysKeyDown = 0x0104;
      const wmSysKeyUp = 0x0105;
      final down = wParam == wmKeyDown || wParam == wmSysKeyDown;
      final up = wParam == wmKeyUp || wParam == wmSysKeyUp;
      if (down || up) {
        try {
          _onKey!(vk, down);
        } catch (_) {}
        return 1; // prevent local Win+Arrow snap etc.
      }
    }
    return _callNextHookEx(_hook, nCode, wParam, lParam);
  }
}
