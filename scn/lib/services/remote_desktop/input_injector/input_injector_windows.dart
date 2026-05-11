import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart';

import 'package:scn/models/remote_desktop_models.dart';
import 'package:scn/services/remote_desktop/input_injector/input_injector.dart';
import 'package:scn/services/remote_desktop/input_injector/win_keymap.dart';
import 'package:scn/utils/logger.dart';

/// Windows-инжектор. Использует `SendInput` с абсолютными координатами
/// в нормированной системе 0..65535, привязанной к виртуальному экрану,
/// чтобы корректно работать с многомониторной конфигурацией.
class WindowsInputInjector implements InputInjector {
  @override
  bool get isAvailable => true;

  @override
  void setTargetSize(int width, int height) {
    // Координаты приходят нормированными 0..1 от viewer, дальше переводим
    // в систему 0..65535 с MOUSEEVENTF_VIRTUALDESK, поэтому конкретный
    // размер захвата на хосте здесь не нужен.
  }

  @override
  void inject(RemoteInputEvent event) {
    switch (event.kind) {
      case RemoteInputEventKind.mouseMove:
        _sendMouseAbsolute(event.x ?? 0, event.y ?? 0);
        break;
      case RemoteInputEventKind.mouseDown:
        _sendMouseButton(event.button, down: true, x: event.x, y: event.y);
        break;
      case RemoteInputEventKind.mouseUp:
        _sendMouseButton(event.button, down: false, x: event.x, y: event.y);
        break;
      case RemoteInputEventKind.mouseScroll:
        _sendMouseScroll(
          dx: event.scrollDeltaX ?? 0,
          dy: event.scrollDeltaY ?? 0,
        );
        break;
      case RemoteInputEventKind.keyDown:
        _sendKey(event, down: true);
        break;
      case RemoteInputEventKind.keyUp:
        _sendKey(event, down: false);
        break;
      case RemoteInputEventKind.textInput:
        _sendText(event.text ?? '');
        break;
      case RemoteInputEventKind.clipboardPaste:
        unawaited(_pasteClipboardText(event.text ?? ''));
        break;
    }
  }

  void _sendMouseAbsolute(double normX, double normY) {
    final point = _screenPoint(normX, normY);
    SetCursorPos(point.$1, point.$2);
    // Нормируем 0..1 -> 0..65535 для MOUSEEVENTF_ABSOLUTE.
    final x = _absoluteCoord(point.$1, _virtualLeft, _virtualWidth);
    final y = _absoluteCoord(point.$2, _virtualTop, _virtualHeight);
    _sendOneMouseEvent(
      flags: MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK,
      x: x,
      y: y,
    );
  }

  void _sendMouseButton(RemoteMouseButton? button,
      {required bool down, double? x, double? y}) {
    int flags = 0;
    int data = 0;
    switch (button ?? RemoteMouseButton.left) {
      case RemoteMouseButton.left:
        flags |= down ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP;
        break;
      case RemoteMouseButton.right:
        flags |= down ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_RIGHTUP;
        break;
      case RemoteMouseButton.middle:
        flags |= down ? MOUSEEVENTF_MIDDLEDOWN : MOUSEEVENTF_MIDDLEUP;
        break;
      case RemoteMouseButton.x1:
        flags |= down ? MOUSEEVENTF_XDOWN : MOUSEEVENTF_XUP;
        data = 0x0001; // XBUTTON1
        break;
      case RemoteMouseButton.x2:
        flags |= down ? MOUSEEVENTF_XDOWN : MOUSEEVENTF_XUP;
        data = 0x0002; // XBUTTON2
        break;
    }
    if (x != null && y != null) {
      // Сначала явно ставим курсор в точку, затем отдельным событием жмём
      // кнопку. Некоторые приложения/заголовки окон хуже обрабатывают
      // "move + button" в одном INPUT, особенно рядом с системными кнопками.
      final point = _screenPoint(x, y);
      SetCursorPos(point.$1, point.$2);
    }
    _sendOneMouseEvent(flags: flags, mouseData: data);
  }

  int get _virtualLeft =>
      GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_XVIRTUALSCREEN);
  int get _virtualTop =>
      GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_YVIRTUALSCREEN);
  int get _virtualWidth =>
      GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CXVIRTUALSCREEN);
  int get _virtualHeight =>
      GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CYVIRTUALSCREEN);

  (int, int) _screenPoint(double normX, double normY) {
    final width = _virtualWidth <= 0
        ? GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CXSCREEN)
        : _virtualWidth;
    final height = _virtualHeight <= 0
        ? GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CYSCREEN)
        : _virtualHeight;
    final left = _virtualWidth <= 0 ? 0 : _virtualLeft;
    final top = _virtualHeight <= 0 ? 0 : _virtualTop;
    final x = left + (normX.clamp(0.0, 1.0) * (width - 1)).round();
    final y = top + (normY.clamp(0.0, 1.0) * (height - 1)).round();
    return (x, y);
  }

  int _absoluteCoord(int value, int origin, int extent) {
    if (extent <= 1) return 0;
    return (((value - origin) * 65535) / (extent - 1)).round().clamp(0, 65535);
  }

  void _sendMouseScroll({required double dx, required double dy}) {
    if (dy != 0) {
      _sendOneMouseEvent(
        flags: MOUSEEVENTF_WHEEL,
        mouseData: dy.round(),
      );
    }
    if (dx != 0) {
      _sendOneMouseEvent(
        flags: MOUSEEVENTF_HWHEEL,
        mouseData: dx.round(),
      );
    }
  }

  void _sendKey(RemoteInputEvent event, {required bool down}) {
    final vk = WinKeymap.virtualKeyForLogicalKey(event.keyCode) ??
        WinKeymap.virtualKeyForPhysicalKey(event.physicalKeyCode);
    if (vk == null) {
      // Если не удалось смапить keycode — пробуем как unicode-символ.
      final text = event.text;
      if (text != null && text.isNotEmpty) {
        _sendUnicodeChar(text.codeUnitAt(0), down: down);
      }
      return;
    }
    final hint = event.text;
    _sendVirtualKey(vk, down: down, charHint: hint);
  }

  void _sendVirtualKey(int vk, {required bool down, String? charHint}) {
    final scan = MapVirtualKey(vk, MAP_VIRTUAL_KEY_TYPE.MAPVK_VK_TO_VSC);
    int flags = 0;
    if (!down) flags |= KEYEVENTF_KEYUP;
    if (WinKeymap.isExtendedKey(vk)) {
      flags |= KEYEVENTF_EXTENDEDKEY;
    }
    final pInputs = calloc<INPUT>();
    try {
      pInputs.ref.type = INPUT_KEYBOARD;
      final ki = pInputs.ref.ki;
      ki.wVk = vk;
      ki.wScan = scan;
      ki.dwFlags = flags;
      ki.time = 0;
      ki.dwExtraInfo = 0;
      _sendInput(1, pInputs);
    } finally {
      calloc.free(pInputs);
    }
    // Фолбэк для окон, защищённых UIPI (UAC consent.exe и т.п.):
    // SendInput туда не доходит из-за разных integrity levels, но
    // PostMessage с WM_KEYDOWN/WM_KEYUP/WM_CHAR разрешён по дефолтному
    // фильтру UIPI и попадает в фокусный контрол.
    _postKeyToElevatedForeground(vk, scan, down: down, charHint: charHint);
  }

  void _sendUnicodeChar(int charCode, {required bool down}) {
    final pInputs = calloc<INPUT>();
    try {
      pInputs.ref.type = INPUT_KEYBOARD;
      final ki = pInputs.ref.ki;
      ki.wVk = 0;
      ki.wScan = charCode;
      ki.dwFlags = KEYEVENTF_UNICODE | (down ? 0 : KEYEVENTF_KEYUP);
      ki.time = 0;
      ki.dwExtraInfo = 0;
      _sendInput(1, pInputs);
    } finally {
      calloc.free(pInputs);
    }
    if (down) {
      _postCharToElevatedForeground(charCode);
    }
  }

  void _sendText(String text) {
    for (final code in text.codeUnits) {
      _sendUnicodeChar(code, down: true);
      _sendUnicodeChar(code, down: false);
    }
  }

  // -- UIPI fallback (PostMessage) --

  /// Кэш HWND и pid foreground-окна, чтобы не дёргать
  /// QueryFullProcessImageName на каждое нажатие.
  int _cachedFgHwnd = 0;
  bool _cachedFgIsElevated = false;
  DateTime _cachedFgCheckedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Возвращает HWND foreground-окна, если оно принадлежит процессу
  /// с более высоким integrity level (UAC consent.exe и пр.).
  /// Иначе возвращает null.
  int? _elevatedForegroundHwnd() {
    final hwnd = GetForegroundWindow();
    if (hwnd == 0) return null;
    final now = DateTime.now();
    if (hwnd == _cachedFgHwnd &&
        now.difference(_cachedFgCheckedAt).inMilliseconds < 500) {
      return _cachedFgIsElevated ? hwnd : null;
    }
    _cachedFgHwnd = hwnd;
    _cachedFgCheckedAt = now;
    _cachedFgIsElevated = _isHwndElevated(hwnd);
    return _cachedFgIsElevated ? hwnd : null;
  }

  bool _isHwndElevated(int hwnd) {
    final pidPtr = calloc<Uint32>();
    try {
      GetWindowThreadProcessId(hwnd, pidPtr);
      final pid = pidPtr.value;
      if (pid == 0) return false;
      final hProc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
      if (hProc == 0) return false;
      try {
        final buf = wsalloc(MAX_PATH);
        final sizePtr = calloc<Uint32>()..value = MAX_PATH;
        try {
          final ok = QueryFullProcessImageName(hProc, 0, buf, sizePtr);
          if (ok == 0) return false;
          final path = buf.toDartString().toLowerCase();
          // consent.exe — UAC consent UI. Остальные системные диалоги
          // (Защитник Windows и т.п.) тоже стоит ловить, но consent.exe
          // покрывает основной кейс.
          if (path.endsWith(r'\consent.exe')) return true;
          if (path.endsWith(r'\lsass.exe')) return true;
          return false;
        } finally {
          free(buf);
          calloc.free(sizePtr);
        }
      } finally {
        CloseHandle(hProc);
      }
    } finally {
      calloc.free(pidPtr);
    }
  }

  /// Находит фокусный HWND внутри указанного окна и постит туда WM_KEYDOWN/UP.
  /// Для печатаемых клавиш дополнительно постит WM_CHAR.
  void _postKeyToElevatedForeground(int vk, int scan,
      {required bool down, String? charHint}) {
    final fg = _elevatedForegroundHwnd();
    if (fg == null) return;
    final target = _focusHwndFor(fg) ?? fg;
    int lParam = 1 | (scan << 16);
    if (WinKeymap.isExtendedKey(vk)) {
      lParam |= 1 << 24;
    }
    if (down) {
      PostMessage(target, WM_KEYDOWN, vk, lParam);
      if (charHint != null && charHint.isNotEmpty) {
        PostMessage(target, WM_CHAR, charHint.codeUnitAt(0), lParam);
      } else {
        // Эмулируем стандартную раскладку: ToUnicode на хосте может
        // выдать символ для VK без явного charHint.
        final ch = _vkToChar(vk);
        if (ch != null) {
          PostMessage(target, WM_CHAR, ch, lParam);
        }
      }
    } else {
      lParam |= 0x3 << 30; // previous state set + transition state set
      PostMessage(target, WM_KEYUP, vk, lParam);
    }
  }

  void _postCharToElevatedForeground(int charCode) {
    final fg = _elevatedForegroundHwnd();
    if (fg == null) return;
    final target = _focusHwndFor(fg) ?? fg;
    PostMessage(target, WM_CHAR, charCode, 1);
  }

  int? _focusHwndFor(int hwnd) {
    final tid = GetWindowThreadProcessId(hwnd, nullptr);
    if (tid == 0) return null;
    final gtiPtr = calloc<GUITHREADINFO>();
    try {
      gtiPtr.ref.cbSize = sizeOf<GUITHREADINFO>();
      if (GetGUIThreadInfo(tid, gtiPtr) == 0) return null;
      final hf = gtiPtr.ref.hwndFocus;
      if (hf != 0) return hf;
      final hCaret = gtiPtr.ref.hwndCaret;
      if (hCaret != 0) return hCaret;
      return null;
    } finally {
      calloc.free(gtiPtr);
    }
  }

  int? _vkToChar(int vk) {
    if (vk >= 0x30 && vk <= 0x39) return vk; // '0'..'9'
    if (vk >= 0x41 && vk <= 0x5A) return vk + 0x20; // 'a'..'z' (lower)
    switch (vk) {
      case 0x08:
        return 0x08; // BACK
      case 0x09:
        return 0x09; // TAB
      case 0x0D:
        return 0x0D; // RETURN
      case 0x1B:
        return 0x1B; // ESC
      case 0x20:
        return 0x20; // SPACE
    }
    return null;
  }

  Future<void> _pasteClipboardText(String text) async {
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    // Ctrl may already be held because the viewer detected Ctrl+V after
    // forwarding Ctrl-down. Reset modifiers before issuing a clean paste.
    _sendVirtualKey(WinKeymap.VK_LCONTROL, down: false);
    _sendVirtualKey(WinKeymap.VK_RCONTROL, down: false);
    _sendVirtualKey(WinKeymap.VK_LMENU, down: false);
    _sendVirtualKey(WinKeymap.VK_RMENU, down: false);
    _sendVirtualKey(WinKeymap.VK_LWIN, down: false);
    _sendVirtualKey(WinKeymap.VK_RWIN, down: false);
    _sendVirtualKey(WinKeymap.VK_CONTROL, down: true);
    _sendVirtualKey(0x56, down: true); // V
    _sendVirtualKey(0x56, down: false);
    _sendVirtualKey(WinKeymap.VK_CONTROL, down: false);
  }

  void _sendOneMouseEvent({
    required int flags,
    int x = 0,
    int y = 0,
    int mouseData = 0,
  }) {
    final pInputs = calloc<INPUT>();
    try {
      pInputs.ref.type = INPUT_MOUSE;
      final mi = pInputs.ref.mi;
      mi.dx = x;
      mi.dy = y;
      mi.mouseData = mouseData;
      mi.dwFlags = flags;
      mi.time = 0;
      mi.dwExtraInfo = 0;
      _sendInput(1, pInputs);
    } finally {
      calloc.free(pInputs);
    }
  }

  void _sendInput(int count, Pointer<INPUT> inputs) {
    final sent = SendInput(count, inputs, sizeOf<INPUT>());
    if (sent != count) {
      AppLogger.log(
        'WindowsInputInjector: SendInput sent $sent/$count, '
        'lastError=${GetLastError()}. '
        'If target window is elevated, run SCN as administrator.',
      );
    }
  }

  @override
  void dispose() {}
}
