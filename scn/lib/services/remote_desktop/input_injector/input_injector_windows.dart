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
    setCaptureRect(width: width, height: height);
  }

  @override
  void setCaptureRect({
    int left = 0,
    int top = 0,
    required int width,
    required int height,
  }) {
    if (width <= 0 || height <= 0) return;
    _captureLeft = left;
    _captureTop = top;
    _captureWidth = width;
    _captureHeight = height;
  }

  int? _captureLeft;
  int? _captureTop;
  int? _captureWidth;
  int? _captureHeight;

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
      // Absolute coords + button in the same SendInput — required for
      // Win7 shell (tray, taskbar, Start). Separate move-then-click often
      // loses the click on non-client / notification-area targets.
      final point = _screenPoint(x, y);
      SetCursorPos(point.$1, point.$2);
      if (down) {
        _softActivateUnderCursor(point.$1, point.$2);
      }
      final ax = _absoluteCoord(point.$1, _virtualLeft, _virtualWidth);
      final ay = _absoluteCoord(point.$2, _virtualTop, _virtualHeight);
      _sendOneMouseEvent(
        flags: flags |
            MOUSEEVENTF_ABSOLUTE |
            MOUSEEVENTF_VIRTUALDESK,
        x: ax,
        y: ay,
        mouseData: data,
      );
      return;
    }
    _sendOneMouseEvent(flags: flags, mouseData: data);
  }

  /// Bring a normal app window under the cursor to the foreground.
  /// Skips shell chrome (taskbar/tray) — those need the click itself, not focus steal.
  void _softActivateUnderCursor(int screenX, int screenY) {
    final pt = calloc<POINT>();
    try {
      pt.ref.x = screenX;
      pt.ref.y = screenY;
      var hwnd = WindowFromPoint(pt.ref);
      if (hwnd == 0) return;
      final root = GetAncestor(hwnd, GET_ANCESTOR_FLAGS.GA_ROOT);
      if (root != 0) hwnd = root;

      if (_isShellChromeHwnd(hwnd)) return;

      final pidPtr = calloc<Uint32>();
      try {
        GetWindowThreadProcessId(hwnd, pidPtr);
        if (pidPtr.value == 0 || pidPtr.value == GetCurrentProcessId()) {
          return;
        }
      } finally {
        calloc.free(pidPtr);
      }

      if (GetForegroundWindow() == hwnd) return;

      final attachedTid = _attachToHwndThread(hwnd);
      try {
        ShowWindow(hwnd, SHOW_WINDOW_CMD.SW_SHOWNOACTIVATE);
        BringWindowToTop(hwnd);
        SetForegroundWindow(hwnd);
      } finally {
        if (attachedTid != null) _detachFromThread(attachedTid);
      }
    } finally {
      calloc.free(pt);
    }
  }

  bool _isShellChromeHwnd(int hwnd) {
    final cls = wsalloc(256);
    try {
      if (GetClassName(hwnd, cls, 256) == 0) return false;
      final name = cls.toDartString();
      return name == 'Shell_TrayWnd' ||
          name == 'Shell_SecondaryTrayWnd' ||
          name == 'NotifyIconOverflowWindow' ||
          name == 'Progman' ||
          name == 'WorkerW' ||
          name.startsWith('Windows.UI.');
    } finally {
      free(cls);
    }
  }

  int get _virtualLeft =>
      GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_XVIRTUALSCREEN);
  int get _virtualTop =>
      GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_YVIRTUALSCREEN);
  int get _virtualWidth =>
      GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CXVIRTUALSCREEN);
  int get _virtualHeight =>
      GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CYVIRTUALSCREEN);

  /// Primary monitor in virtual-desktop coordinates.
  /// GDI frame capture uses the same rect — not the full virtual screen.
  (int left, int top, int width, int height) _primaryMonitorRect() {
    final hmon = MonitorFromWindow(
      GetDesktopWindow(),
      MONITOR_FROM_FLAGS.MONITOR_DEFAULTTOPRIMARY,
    );
    if (hmon != 0) {
      final info = calloc<MONITORINFO>();
      try {
        info.ref.cbSize = sizeOf<MONITORINFO>();
        if (GetMonitorInfo(hmon, info) != 0) {
          final r = info.ref.rcMonitor;
          final w = r.right - r.left;
          final h = r.bottom - r.top;
          if (w > 0 && h > 0) {
            return (r.left, r.top, w, h);
          }
        }
      } finally {
        calloc.free(info);
      }
    }
    final w = GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CXSCREEN);
    final h = GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CYSCREEN);
    return (0, 0, w > 0 ? w : 1, h > 0 ? h : 1);
  }

  (int, int) _screenPoint(double normX, double normY) {
    final rect = (_captureWidth != null && _captureHeight != null)
        ? (
            _captureLeft ?? 0,
            _captureTop ?? 0,
            _captureWidth!,
            _captureHeight!,
          )
        : _primaryMonitorRect();
    final x = rect.$1 + (normX.clamp(0.0, 1.0) * (rect.$3 - 1)).round();
    final y = rect.$2 + (normY.clamp(0.0, 1.0) * (rect.$4 - 1)).round();
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
    // Если foreground — elevated окно, перед SendInput цепляем нашу
    // input-очередь к его потоку. Иногда этого достаточно, чтобы пройти
    // фильтр UIPI для клавиатуры.
    final elevatedHwnd = _elevatedForegroundHwnd();
    int? attachedTid;
    if (elevatedHwnd != null) {
      attachedTid = _attachToHwndThread(elevatedHwnd);
    }
    try {
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
    } finally {
      if (attachedTid != null) _detachFromThread(attachedTid);
    }
    // Дополнительный фолбэк для UAC и других elevated окон:
    // напрямую посылаем оконные сообщения в фокусный HWND.
    if (elevatedHwnd != null) {
      _postKeyToHwnd(elevatedHwnd, vk, scan,
          down: down, charHint: charHint);
    }
  }

  void _sendUnicodeChar(int charCode, {required bool down}) {
    final elevatedHwnd = _elevatedForegroundHwnd();
    int? attachedTid;
    if (elevatedHwnd != null) {
      attachedTid = _attachToHwndThread(elevatedHwnd);
    }
    try {
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
    } finally {
      if (attachedTid != null) _detachFromThread(attachedTid);
    }
    if (down && elevatedHwnd != null) {
      _postCharToHwnd(elevatedHwnd, charCode);
    }
  }

  void _sendText(String text) {
    for (final code in text.codeUnits) {
      _sendUnicodeChar(code, down: true);
      _sendUnicodeChar(code, down: false);
    }
  }

  int? _attachToHwndThread(int hwnd) {
    final targetTid = GetWindowThreadProcessId(hwnd, nullptr);
    if (targetTid == 0) return null;
    final ourTid = GetCurrentThreadId();
    if (ourTid == targetTid) return null;
    final ok = AttachThreadInput(ourTid, targetTid, TRUE);
    if (ok == 0) return null;
    return targetTid;
  }

  void _detachFromThread(int targetTid) {
    final ourTid = GetCurrentThreadId();
    AttachThreadInput(ourTid, targetTid, FALSE);
  }

  // -- UIPI fallback --

  int _cachedFgHwnd = 0;
  bool _cachedFgIsElevated = false;
  String _cachedFgProcessName = '';
  DateTime _cachedFgCheckedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Возвращает HWND foreground-окна, если оно скорее всего защищено UIPI
  /// (UAC consent.exe, credential UI, lsass, etc). Иначе null.
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
    final detected = _detectForegroundProcess(hwnd);
    _cachedFgProcessName = detected;
    _cachedFgIsElevated = _isProcessElevated(detected);
    if (_cachedFgIsElevated) {
      AppLogger.log(
          'WindowsInputInjector: elevated foreground=$detected (hwnd=$hwnd) — '
          'using PostMessage fallback');
    }
    return _cachedFgIsElevated ? hwnd : null;
  }

  String _detectForegroundProcess(int hwnd) {
    final pidPtr = calloc<Uint32>();
    try {
      GetWindowThreadProcessId(hwnd, pidPtr);
      final pid = pidPtr.value;
      if (pid == 0) return '';
      final hProc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
      if (hProc == 0) return '';
      try {
        final buf = wsalloc(MAX_PATH);
        final sizePtr = calloc<Uint32>()..value = MAX_PATH;
        try {
          final ok = QueryFullProcessImageName(hProc, 0, buf, sizePtr);
          if (ok == 0) return '';
          return buf.toDartString();
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

  bool _isProcessElevated(String fullPath) {
    if (fullPath.isEmpty) return false;
    final lower = fullPath.toLowerCase();
    const elevatedNames = [
      r'\consent.exe',
      r'\lsass.exe',
      r'\credentialuibroker.exe',
      r'\logonui.exe',
      r'\runas.exe',
      r'\securityhealthsystray.exe',
    ];
    for (final name in elevatedNames) {
      if (lower.endsWith(name)) return true;
    }
    return false;
  }

  void _postKeyToHwnd(int fg, int vk, int scan,
      {required bool down, String? charHint}) {
    final target = _focusHwndFor(fg) ?? fg;
    int lParam = 1 | (scan << 16);
    if (WinKeymap.isExtendedKey(vk)) {
      lParam |= 1 << 24;
    }
    if (down) {
      // Используем SendMessage (sync), чтобы XAML-host консента успел
      // обработать сообщение до следующего keystroke. После него
      // дублируем PostMessage — некоторые контролы реагируют только на
      // async очередь.
      SendMessage(target, WM_KEYDOWN, vk, lParam);
      PostMessage(target, WM_KEYDOWN, vk, lParam);
      int? charCode;
      if (charHint != null && charHint.isNotEmpty) {
        charCode = charHint.codeUnitAt(0);
      } else {
        charCode = _vkToChar(vk);
      }
      if (charCode != null) {
        SendMessage(target, WM_CHAR, charCode, lParam);
        PostMessage(target, WM_CHAR, charCode, lParam);
      }
    } else {
      lParam |= 0x3 << 30;
      SendMessage(target, WM_KEYUP, vk, lParam);
      PostMessage(target, WM_KEYUP, vk, lParam);
    }
  }

  void _postCharToHwnd(int fg, int charCode) {
    final target = _focusHwndFor(fg) ?? fg;
    final scan = MapVirtualKey(charCode, MAP_VIRTUAL_KEY_TYPE.MAPVK_VK_TO_VSC);
    final lParam = 1 | (scan << 16);
    SendMessage(target, WM_CHAR, charCode, lParam);
    PostMessage(target, WM_CHAR, charCode, lParam);
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
