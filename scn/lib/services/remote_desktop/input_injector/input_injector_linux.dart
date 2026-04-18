import 'dart:async';
import 'dart:io';

import 'package:scn/models/remote_desktop_models.dart';
import 'package:scn/services/remote_desktop/input_injector/input_injector.dart';

/// Linux реализация через `xdotool` (X11) или `ydotool` (Wayland).
/// Утилиты должны быть установлены отдельно.
class LinuxInputInjector implements InputInjector {
  bool? _hasXdotool;
  bool? _hasYdotool;
  int _targetW = 1920;
  int _targetH = 1080;

  @override
  bool get isAvailable => true;

  @override
  void setTargetSize(int width, int height) {
    if (width > 0) _targetW = width;
    if (height > 0) _targetH = height;
  }

  Future<void> _detect() async {
    if (_hasXdotool != null) return;
    try {
      final r1 = await Process.run('which', ['xdotool']);
      _hasXdotool = r1.exitCode == 0;
    } catch (_) {
      _hasXdotool = false;
    }
    try {
      final r2 = await Process.run('which', ['ydotool']);
      _hasYdotool = r2.exitCode == 0;
    } catch (_) {
      _hasYdotool = false;
    }
  }

  String? _tool() {
    if (_hasXdotool == true) return 'xdotool';
    if (_hasYdotool == true) return 'ydotool';
    return null;
  }

  @override
  void inject(RemoteInputEvent event) {
    unawaited(_inject(event));
  }

  Future<void> _inject(RemoteInputEvent event) async {
    await _detect();
    final tool = _tool();
    if (tool == null) return;

    switch (event.kind) {
      case RemoteInputEventKind.mouseMove:
        final pt = _toPoint(event.x, event.y);
        if (pt == null) return;
        if (tool == 'xdotool') {
          await Process.run(tool, ['mousemove', '${pt.$1}', '${pt.$2}']);
        } else {
          await Process.run(tool,
              ['mousemove_abs', '--', '${pt.$1}', '${pt.$2}']);
        }
        break;
      case RemoteInputEventKind.mouseDown:
        final btn = _xdotoolBtn(event.button);
        if (tool == 'xdotool') {
          await Process.run(tool, ['mousedown', '$btn']);
        } else {
          await Process.run(tool, ['click', '$btn']);
        }
        break;
      case RemoteInputEventKind.mouseUp:
        final btn = _xdotoolBtn(event.button);
        if (tool == 'xdotool') {
          await Process.run(tool, ['mouseup', '$btn']);
        }
        break;
      case RemoteInputEventKind.mouseScroll:
        final dy = event.scrollDeltaY ?? 0;
        if (dy != 0) {
          final btn = dy > 0 ? '5' : '4';
          if (tool == 'xdotool') {
            await Process.run(tool, ['click', btn]);
          }
        }
        break;
      case RemoteInputEventKind.keyDown:
      case RemoteInputEventKind.keyUp:
        final keysym = _keysymFor(event);
        if (keysym == null) return;
        if (tool == 'xdotool') {
          final action =
              event.kind == RemoteInputEventKind.keyDown ? 'keydown' : 'keyup';
          await Process.run(tool, [action, keysym]);
        }
        break;
      case RemoteInputEventKind.textInput:
        final text = event.text;
        if (text == null || text.isEmpty) return;
        if (tool == 'xdotool') {
          await Process.run(tool, ['type', '--', text]);
        } else {
          await Process.run(tool, ['type', text]);
        }
        break;
    }
  }

  int _xdotoolBtn(RemoteMouseButton? btn) {
    switch (btn ?? RemoteMouseButton.left) {
      case RemoteMouseButton.right:
        return 3;
      case RemoteMouseButton.middle:
        return 2;
      case RemoteMouseButton.x1:
        return 8;
      case RemoteMouseButton.x2:
        return 9;
      default:
        return 1;
    }
  }

  (int, int)? _toPoint(double? nx, double? ny) {
    if (nx == null || ny == null) return null;
    final x = (nx.clamp(0.0, 1.0) * _targetW).round();
    final y = (ny.clamp(0.0, 1.0) * _targetH).round();
    return (x, y);
  }

  /// Маппинг популярных Flutter logical keys в X11 keysym имена.
  String? _keysymFor(RemoteInputEvent event) {
    final txt = event.text;
    if (txt != null && txt.isNotEmpty) {
      // Просто символ в keysym имя через "U+XXXX".
      final code = txt.codeUnitAt(0);
      return 'U${code.toRadixString(16).toUpperCase().padLeft(4, '0')}';
    }
    // Дополнительные жёстко прошитые имена для управляющих клавиш можно
    // добавить позже. Здесь обходимся текстом.
    return null;
  }

  @override
  void dispose() {}
}
