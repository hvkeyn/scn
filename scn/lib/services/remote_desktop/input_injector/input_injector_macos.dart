import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:scn/models/remote_desktop_models.dart';
import 'package:scn/services/remote_desktop/input_injector/input_injector.dart';

/// macOS реализация через `cliclick` или fallback `osascript`.
/// `cliclick` (https://github.com/BlueM/cliclick, доступен в Homebrew)
/// даёт быстрые и точные события мыши/клавиатуры. Если его нет —
/// откатываемся на медленный `osascript` через `tell application "System Events"`.
class MacOsInputInjector implements InputInjector {
  bool? _hasCliclick;
  int _targetW = 1920;
  int _targetH = 1080;

  @override
  bool get isAvailable => true;

  @override
  void setTargetSize(int width, int height) {
    if (width > 0) _targetW = width;
    if (height > 0) _targetH = height;
  }

  Future<bool> _ensureCliclick() async {
    if (_hasCliclick != null) return _hasCliclick!;
    try {
      final res = await Process.run('which', ['cliclick']);
      _hasCliclick = res.exitCode == 0;
    } catch (_) {
      _hasCliclick = false;
    }
    return _hasCliclick!;
  }

  @override
  void inject(RemoteInputEvent event) {
    unawaited(_inject(event));
  }

  Future<void> _inject(RemoteInputEvent event) async {
    final cliclick = await _ensureCliclick();
    switch (event.kind) {
      case RemoteInputEventKind.mouseMove:
        final pt = _toPoint(event.x, event.y);
        if (pt == null) return;
        if (cliclick) {
          await Process.run('cliclick', ['m:${pt.$1},${pt.$2}']);
        } else {
          await _osascript(
              'tell application "System Events" to set the position of '
              'mouse to {${pt.$1}, ${pt.$2}}');
        }
        break;
      case RemoteInputEventKind.mouseDown:
        final pt = _toPoint(event.x, event.y);
        if (pt == null) return;
        if (cliclick) {
          final cmd = _buttonPrefix(event.button, down: true);
          await Process.run('cliclick', ['$cmd:${pt.$1},${pt.$2}']);
        } else {
          await _osascript(
              'tell application "System Events" to click at {${pt.$1}, ${pt.$2}}');
        }
        break;
      case RemoteInputEventKind.mouseUp:
        if (cliclick) {
          final pt = _toPoint(event.x, event.y);
          if (pt == null) return;
          final cmd = _buttonPrefix(event.button, down: false);
          await Process.run('cliclick', ['$cmd:${pt.$1},${pt.$2}']);
        }
        break;
      case RemoteInputEventKind.mouseScroll:
        final dx = event.scrollDeltaX ?? 0;
        final dy = event.scrollDeltaY ?? 0;
        if (cliclick) {
          if (dy != 0) {
            await Process.run('cliclick', ['w:0,${dy.round()}']);
          }
          if (dx != 0) {
            await Process.run('cliclick', ['w:${dx.round()},0']);
          }
        }
        break;
      case RemoteInputEventKind.keyDown:
        await _sendKey(event, down: true, cliclick: cliclick);
        break;
      case RemoteInputEventKind.keyUp:
        await _sendKey(event, down: false, cliclick: cliclick);
        break;
      case RemoteInputEventKind.textInput:
        if (event.text != null) {
          if (cliclick) {
            await Process.run('cliclick', ['t:${event.text}']);
          } else {
            await _osascript(
                'tell application "System Events" to keystroke "${_escape(event.text!)}"');
          }
        }
        break;
      case RemoteInputEventKind.clipboardPaste:
        final text = event.text;
        if (text == null || text.isEmpty) return;
        await Clipboard.setData(ClipboardData(text: text));
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await _osascript(
            'tell application "System Events" to keystroke "v" using command down');
        break;
    }
  }

  Future<void> _sendKey(RemoteInputEvent event,
      {required bool down, required bool cliclick}) async {
    if (event.ctrl || event.meta || event.alt) {
      final key = _keyNameFor(event);
      if (key == null) return;
      final modifiers = <String>[
        if (event.ctrl) 'control',
        if (event.meta) 'command',
        if (event.alt) 'option',
        if (event.shift) 'shift',
      ];
      if (cliclick && modifiers.isEmpty) {
        await Process.run('cliclick', ['kp:$key']);
        return;
      }
      if (down) {
        final using = modifiers.isEmpty
            ? ''
            : ' using {${modifiers.map((m) => '$m down').join(', ')}}';
        await _osascript(
            'tell application "System Events" to keystroke "$key"$using');
      }
      return;
    }
    final ch = event.text;
    if (ch != null && ch.isNotEmpty && down) {
      if (cliclick) {
        await Process.run('cliclick', ['t:$ch']);
      } else {
        await _osascript(
            'tell application "System Events" to keystroke "${_escape(ch)}"');
      }
    }
  }

  String? _keyNameFor(RemoteInputEvent event) {
    final code = event.keyCode;
    if (code == null) return null;
    if (code >= 0x61 && code <= 0x7a) {
      return String.fromCharCode(code);
    }
    if (code >= 0x30 && code <= 0x39) {
      return String.fromCharCode(code);
    }
    switch (code) {
      case 4294967305:
        return '\b';
      case 4294967306:
        return '\t';
      case 4294967309:
        return '\n';
      case 4294967323:
        return '\u001b';
      case 4294967332:
        return ' ';
    }
    return null;
  }

  String _buttonPrefix(RemoteMouseButton? btn, {required bool down}) {
    switch (btn ?? RemoteMouseButton.left) {
      case RemoteMouseButton.right:
        return down ? 'rd' : 'ru';
      case RemoteMouseButton.middle:
        // cliclick не имеет дискретного middle — приближаем кликом.
        return down ? 'dd' : 'du';
      default:
        return down ? 'dd' : 'du';
    }
  }

  (int, int)? _toPoint(double? nx, double? ny) {
    if (nx == null || ny == null) return null;
    final x = (nx.clamp(0.0, 1.0) * _targetW).round();
    final y = (ny.clamp(0.0, 1.0) * _targetH).round();
    return (x, y);
  }

  Future<ProcessResult> _osascript(String script) {
    return Process.run('osascript', ['-e', script]);
  }

  String _escape(String s) => s.replaceAll('"', r'\"');

  @override
  void dispose() {}
}
