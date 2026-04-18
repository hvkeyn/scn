import 'package:flutter/services.dart';

/// Маппинг Flutter LogicalKeyboardKey/PhysicalKeyboardKey в Windows VK codes.
class WinKeymap {
  /// Конвертирует Flutter [LogicalKeyboardKey.keyId] в Win32 VK code.
  static int? virtualKeyForLogicalKey(int? keyId) {
    if (keyId == null) return null;
    final cached = _logicalToVk[keyId];
    if (cached != null) return cached;
    return null;
  }

  /// Fallback: USB HID -> VK по physical key.
  static int? virtualKeyForPhysicalKey(int? usbHid) {
    if (usbHid == null) return null;
    return _physicalToVk[usbHid];
  }

  /// Клавиши, которые требуют флаг KEYEVENTF_EXTENDEDKEY.
  static bool isExtendedKey(int vk) => _extendedKeys.contains(vk);

  // --- VK constants ---
  static const int VK_BACK = 0x08;
  static const int VK_TAB = 0x09;
  static const int VK_RETURN = 0x0D;
  static const int VK_SHIFT = 0x10;
  static const int VK_CONTROL = 0x11;
  static const int VK_MENU = 0x12;
  static const int VK_PAUSE = 0x13;
  static const int VK_CAPITAL = 0x14;
  static const int VK_ESCAPE = 0x1B;
  static const int VK_SPACE = 0x20;
  static const int VK_PRIOR = 0x21;
  static const int VK_NEXT = 0x22;
  static const int VK_END = 0x23;
  static const int VK_HOME = 0x24;
  static const int VK_LEFT = 0x25;
  static const int VK_UP = 0x26;
  static const int VK_RIGHT = 0x27;
  static const int VK_DOWN = 0x28;
  static const int VK_PRINT = 0x2A;
  static const int VK_SNAPSHOT = 0x2C;
  static const int VK_INSERT = 0x2D;
  static const int VK_DELETE = 0x2E;
  static const int VK_LWIN = 0x5B;
  static const int VK_RWIN = 0x5C;
  static const int VK_APPS = 0x5D;
  static const int VK_F1 = 0x70;
  static const int VK_LSHIFT = 0xA0;
  static const int VK_RSHIFT = 0xA1;
  static const int VK_LCONTROL = 0xA2;
  static const int VK_RCONTROL = 0xA3;
  static const int VK_LMENU = 0xA4;
  static const int VK_RMENU = 0xA5;
  static const int VK_OEM_1 = 0xBA;
  static const int VK_OEM_PLUS = 0xBB;
  static const int VK_OEM_COMMA = 0xBC;
  static const int VK_OEM_MINUS = 0xBD;
  static const int VK_OEM_PERIOD = 0xBE;
  static const int VK_OEM_2 = 0xBF;
  static const int VK_OEM_3 = 0xC0;
  static const int VK_OEM_4 = 0xDB;
  static const int VK_OEM_5 = 0xDC;
  static const int VK_OEM_6 = 0xDD;
  static const int VK_OEM_7 = 0xDE;

  static final Map<int, int> _logicalToVk = {
    LogicalKeyboardKey.backspace.keyId: VK_BACK,
    LogicalKeyboardKey.tab.keyId: VK_TAB,
    LogicalKeyboardKey.enter.keyId: VK_RETURN,
    LogicalKeyboardKey.escape.keyId: VK_ESCAPE,
    LogicalKeyboardKey.space.keyId: VK_SPACE,
    LogicalKeyboardKey.arrowLeft.keyId: VK_LEFT,
    LogicalKeyboardKey.arrowRight.keyId: VK_RIGHT,
    LogicalKeyboardKey.arrowUp.keyId: VK_UP,
    LogicalKeyboardKey.arrowDown.keyId: VK_DOWN,
    LogicalKeyboardKey.home.keyId: VK_HOME,
    LogicalKeyboardKey.end.keyId: VK_END,
    LogicalKeyboardKey.pageUp.keyId: VK_PRIOR,
    LogicalKeyboardKey.pageDown.keyId: VK_NEXT,
    LogicalKeyboardKey.insert.keyId: VK_INSERT,
    LogicalKeyboardKey.delete.keyId: VK_DELETE,
    LogicalKeyboardKey.shiftLeft.keyId: VK_LSHIFT,
    LogicalKeyboardKey.shiftRight.keyId: VK_RSHIFT,
    LogicalKeyboardKey.controlLeft.keyId: VK_LCONTROL,
    LogicalKeyboardKey.controlRight.keyId: VK_RCONTROL,
    LogicalKeyboardKey.altLeft.keyId: VK_LMENU,
    LogicalKeyboardKey.altRight.keyId: VK_RMENU,
    LogicalKeyboardKey.metaLeft.keyId: VK_LWIN,
    LogicalKeyboardKey.metaRight.keyId: VK_RWIN,
    LogicalKeyboardKey.capsLock.keyId: VK_CAPITAL,
    LogicalKeyboardKey.printScreen.keyId: VK_SNAPSHOT,
    LogicalKeyboardKey.pause.keyId: VK_PAUSE,
    LogicalKeyboardKey.contextMenu.keyId: VK_APPS,
    // Letters (a..z) - ascii lower
    for (int i = 0; i < 26; i++) (0x61 + i): 0x41 + i,
    // Digits 0..9
    for (int i = 0; i < 10; i++) (0x30 + i): 0x30 + i,
    // F1..F12
    LogicalKeyboardKey.f1.keyId: VK_F1,
    LogicalKeyboardKey.f2.keyId: VK_F1 + 1,
    LogicalKeyboardKey.f3.keyId: VK_F1 + 2,
    LogicalKeyboardKey.f4.keyId: VK_F1 + 3,
    LogicalKeyboardKey.f5.keyId: VK_F1 + 4,
    LogicalKeyboardKey.f6.keyId: VK_F1 + 5,
    LogicalKeyboardKey.f7.keyId: VK_F1 + 6,
    LogicalKeyboardKey.f8.keyId: VK_F1 + 7,
    LogicalKeyboardKey.f9.keyId: VK_F1 + 8,
    LogicalKeyboardKey.f10.keyId: VK_F1 + 9,
    LogicalKeyboardKey.f11.keyId: VK_F1 + 10,
    LogicalKeyboardKey.f12.keyId: VK_F1 + 11,
    LogicalKeyboardKey.semicolon.keyId: VK_OEM_1,
    LogicalKeyboardKey.equal.keyId: VK_OEM_PLUS,
    LogicalKeyboardKey.comma.keyId: VK_OEM_COMMA,
    LogicalKeyboardKey.minus.keyId: VK_OEM_MINUS,
    LogicalKeyboardKey.period.keyId: VK_OEM_PERIOD,
    LogicalKeyboardKey.slash.keyId: VK_OEM_2,
    LogicalKeyboardKey.backquote.keyId: VK_OEM_3,
    LogicalKeyboardKey.bracketLeft.keyId: VK_OEM_4,
    LogicalKeyboardKey.backslash.keyId: VK_OEM_5,
    LogicalKeyboardKey.bracketRight.keyId: VK_OEM_6,
    LogicalKeyboardKey.quote.keyId: VK_OEM_7,
  };

  static final Map<int, int> _physicalToVk = {
    PhysicalKeyboardKey.keyA.usbHidUsage: 0x41,
    PhysicalKeyboardKey.keyB.usbHidUsage: 0x42,
    PhysicalKeyboardKey.keyC.usbHidUsage: 0x43,
    PhysicalKeyboardKey.keyD.usbHidUsage: 0x44,
    PhysicalKeyboardKey.keyE.usbHidUsage: 0x45,
    PhysicalKeyboardKey.keyF.usbHidUsage: 0x46,
    PhysicalKeyboardKey.keyG.usbHidUsage: 0x47,
    PhysicalKeyboardKey.keyH.usbHidUsage: 0x48,
    PhysicalKeyboardKey.keyI.usbHidUsage: 0x49,
    PhysicalKeyboardKey.keyJ.usbHidUsage: 0x4A,
    PhysicalKeyboardKey.keyK.usbHidUsage: 0x4B,
    PhysicalKeyboardKey.keyL.usbHidUsage: 0x4C,
    PhysicalKeyboardKey.keyM.usbHidUsage: 0x4D,
    PhysicalKeyboardKey.keyN.usbHidUsage: 0x4E,
    PhysicalKeyboardKey.keyO.usbHidUsage: 0x4F,
    PhysicalKeyboardKey.keyP.usbHidUsage: 0x50,
    PhysicalKeyboardKey.keyQ.usbHidUsage: 0x51,
    PhysicalKeyboardKey.keyR.usbHidUsage: 0x52,
    PhysicalKeyboardKey.keyS.usbHidUsage: 0x53,
    PhysicalKeyboardKey.keyT.usbHidUsage: 0x54,
    PhysicalKeyboardKey.keyU.usbHidUsage: 0x55,
    PhysicalKeyboardKey.keyV.usbHidUsage: 0x56,
    PhysicalKeyboardKey.keyW.usbHidUsage: 0x57,
    PhysicalKeyboardKey.keyX.usbHidUsage: 0x58,
    PhysicalKeyboardKey.keyY.usbHidUsage: 0x59,
    PhysicalKeyboardKey.keyZ.usbHidUsage: 0x5A,
    PhysicalKeyboardKey.digit1.usbHidUsage: 0x31,
    PhysicalKeyboardKey.digit2.usbHidUsage: 0x32,
    PhysicalKeyboardKey.digit3.usbHidUsage: 0x33,
    PhysicalKeyboardKey.digit4.usbHidUsage: 0x34,
    PhysicalKeyboardKey.digit5.usbHidUsage: 0x35,
    PhysicalKeyboardKey.digit6.usbHidUsage: 0x36,
    PhysicalKeyboardKey.digit7.usbHidUsage: 0x37,
    PhysicalKeyboardKey.digit8.usbHidUsage: 0x38,
    PhysicalKeyboardKey.digit9.usbHidUsage: 0x39,
    PhysicalKeyboardKey.digit0.usbHidUsage: 0x30,
    PhysicalKeyboardKey.enter.usbHidUsage: VK_RETURN,
    PhysicalKeyboardKey.escape.usbHidUsage: VK_ESCAPE,
    PhysicalKeyboardKey.backspace.usbHidUsage: VK_BACK,
    PhysicalKeyboardKey.tab.usbHidUsage: VK_TAB,
    PhysicalKeyboardKey.space.usbHidUsage: VK_SPACE,
    PhysicalKeyboardKey.minus.usbHidUsage: VK_OEM_MINUS,
    PhysicalKeyboardKey.equal.usbHidUsage: VK_OEM_PLUS,
    PhysicalKeyboardKey.bracketLeft.usbHidUsage: VK_OEM_4,
    PhysicalKeyboardKey.bracketRight.usbHidUsage: VK_OEM_6,
    PhysicalKeyboardKey.backslash.usbHidUsage: VK_OEM_5,
    PhysicalKeyboardKey.semicolon.usbHidUsage: VK_OEM_1,
    PhysicalKeyboardKey.quote.usbHidUsage: VK_OEM_7,
    PhysicalKeyboardKey.backquote.usbHidUsage: VK_OEM_3,
    PhysicalKeyboardKey.comma.usbHidUsage: VK_OEM_COMMA,
    PhysicalKeyboardKey.period.usbHidUsage: VK_OEM_PERIOD,
    PhysicalKeyboardKey.slash.usbHidUsage: VK_OEM_2,
    PhysicalKeyboardKey.capsLock.usbHidUsage: VK_CAPITAL,
    PhysicalKeyboardKey.f1.usbHidUsage: VK_F1,
    PhysicalKeyboardKey.f2.usbHidUsage: VK_F1 + 1,
    PhysicalKeyboardKey.f3.usbHidUsage: VK_F1 + 2,
    PhysicalKeyboardKey.f4.usbHidUsage: VK_F1 + 3,
    PhysicalKeyboardKey.f5.usbHidUsage: VK_F1 + 4,
    PhysicalKeyboardKey.f6.usbHidUsage: VK_F1 + 5,
    PhysicalKeyboardKey.f7.usbHidUsage: VK_F1 + 6,
    PhysicalKeyboardKey.f8.usbHidUsage: VK_F1 + 7,
    PhysicalKeyboardKey.f9.usbHidUsage: VK_F1 + 8,
    PhysicalKeyboardKey.f10.usbHidUsage: VK_F1 + 9,
    PhysicalKeyboardKey.f11.usbHidUsage: VK_F1 + 10,
    PhysicalKeyboardKey.f12.usbHidUsage: VK_F1 + 11,
    PhysicalKeyboardKey.insert.usbHidUsage: VK_INSERT,
    PhysicalKeyboardKey.home.usbHidUsage: VK_HOME,
    PhysicalKeyboardKey.pageUp.usbHidUsage: VK_PRIOR,
    PhysicalKeyboardKey.delete.usbHidUsage: VK_DELETE,
    PhysicalKeyboardKey.end.usbHidUsage: VK_END,
    PhysicalKeyboardKey.pageDown.usbHidUsage: VK_NEXT,
    PhysicalKeyboardKey.arrowRight.usbHidUsage: VK_RIGHT,
    PhysicalKeyboardKey.arrowLeft.usbHidUsage: VK_LEFT,
    PhysicalKeyboardKey.arrowDown.usbHidUsage: VK_DOWN,
    PhysicalKeyboardKey.arrowUp.usbHidUsage: VK_UP,
    PhysicalKeyboardKey.controlLeft.usbHidUsage: VK_LCONTROL,
    PhysicalKeyboardKey.shiftLeft.usbHidUsage: VK_LSHIFT,
    PhysicalKeyboardKey.altLeft.usbHidUsage: VK_LMENU,
    PhysicalKeyboardKey.metaLeft.usbHidUsage: VK_LWIN,
    PhysicalKeyboardKey.controlRight.usbHidUsage: VK_RCONTROL,
    PhysicalKeyboardKey.shiftRight.usbHidUsage: VK_RSHIFT,
    PhysicalKeyboardKey.altRight.usbHidUsage: VK_RMENU,
    PhysicalKeyboardKey.metaRight.usbHidUsage: VK_RWIN,
  };

  static const Set<int> _extendedKeys = {
    VK_RCONTROL,
    VK_RMENU,
    VK_INSERT,
    VK_DELETE,
    VK_HOME,
    VK_END,
    VK_PRIOR,
    VK_NEXT,
    VK_LEFT,
    VK_RIGHT,
    VK_UP,
    VK_DOWN,
    VK_LWIN,
    VK_RWIN,
    VK_APPS,
  };
}
