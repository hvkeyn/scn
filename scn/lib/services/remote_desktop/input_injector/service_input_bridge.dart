import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'package:scn/utils/logger.dart';

/// Клиент именованного канала к привилегированному воркеру ввода
/// (`scn.exe --rd-worker`, работает под LocalSystem в пользовательской
/// сессии). Через него ввод доходит до UAC/secure desktop и окон System
/// integrity, недостижимых для обычного процесса.
///
/// Протокол — фиксированная структура 32 байта (8 × int32), синхронно с
/// `rd_input_service.cpp`:
///   [0] type       (1=mouse, 2=keyboard)
///   [1] mouseFlags (MOUSEEVENTF_*)
///   [2] mouseData  (wheel / XBUTTON)
///   [3] dx         (absolute X 0..65535)
///   [4] dy         (absolute Y 0..65535)
///   [5] wVk        (virtual key)
///   [6] wScan      (scan code / unicode)
///   [7] keyFlags   (KEYEVENTF_*)
class ServiceInputBridge {
  static const String _pipeName = r'\\.\pipe\scn_rd_input';
  static const int _invalidHandle = -1;
  static const int _cmdMouse = 1;
  static const int _cmdKeyboard = 2;

  int _handle = _invalidHandle;
  DateTime _lastAttempt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isConnected => _handle != _invalidHandle;

  /// Пытается (пере)подключиться к каналу воркера. Попытки троттлятся раз в
  /// секунду, чтобы не спамить CreateFile, если сервис не запущен.
  bool ensureConnected() {
    if (isConnected) return true;
    final now = DateTime.now();
    if (now.difference(_lastAttempt).inMilliseconds < 1000) return false;
    _lastAttempt = now;

    final namePtr = _pipeName.toNativeUtf16();
    try {
      final h = CreateFile(
        namePtr,
        GENERIC_WRITE,
        0,
        nullptr,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        0,
      );
      if (h == _invalidHandle) {
        return false;
      }
      _handle = h;
      AppLogger.log('ServiceInputBridge: connected to worker pipe');
      return true;
    } finally {
      calloc.free(namePtr);
    }
  }

  void close() {
    if (_handle != _invalidHandle) {
      CloseHandle(_handle);
      _handle = _invalidHandle;
    }
  }

  bool sendMouse({
    required int flags,
    int mouseData = 0,
    int dx = 0,
    int dy = 0,
  }) =>
      _send(type: _cmdMouse,
          mouseFlags: flags, mouseData: mouseData, dx: dx, dy: dy);

  bool sendKeyboard({int wVk = 0, int wScan = 0, int keyFlags = 0}) =>
      _send(type: _cmdKeyboard, wVk: wVk, wScan: wScan, keyFlags: keyFlags);

  bool _send({
    required int type,
    int mouseFlags = 0,
    int mouseData = 0,
    int dx = 0,
    int dy = 0,
    int wVk = 0,
    int wScan = 0,
    int keyFlags = 0,
  }) {
    if (!ensureConnected()) return false;
    final buf = calloc<Int32>(8);
    final written = calloc<Uint32>();
    try {
      buf[0] = type;
      buf[1] = mouseFlags;
      buf[2] = mouseData;
      buf[3] = dx;
      buf[4] = dy;
      buf[5] = wVk;
      buf[6] = wScan;
      buf[7] = keyFlags;
      final ok = WriteFile(_handle, buf.cast<Uint8>(), 32, written, nullptr);
      if (ok == 0) {
        AppLogger.log('ServiceInputBridge: write failed; dropping connection');
        close();
        return false;
      }
      return true;
    } finally {
      calloc.free(buf);
      calloc.free(written);
    }
  }
}
