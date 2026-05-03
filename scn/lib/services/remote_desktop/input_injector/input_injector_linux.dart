import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:scn/models/remote_desktop_models.dart';
import 'package:scn/services/remote_desktop/input_injector/input_injector.dart';
import 'package:scn/utils/logger.dart';

/// Linux реализация через `xdotool` (X11) или `ydotool` (Wayland).
/// Утилиты должны быть установлены отдельно.
class LinuxInputInjector implements InputInjector {
  bool? _hasXdotool;
  bool? _hasYdotool;
  bool _missingToolLogged = false;
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
    if (_hasXdotool == true) {
      await _detectX11Geometry();
    }
    AppLogger.log(
        'LinuxInputInjector: xdotool=$_hasXdotool ydotool=$_hasYdotool target=${_targetW}x$_targetH session=${Platform.environment['XDG_SESSION_TYPE'] ?? 'unknown'}');
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
    if (tool == null) {
      if (!_missingToolLogged) {
        _missingToolLogged = true;
        AppLogger.log(
          'LinuxInputInjector: no input tool found. Install xdotool for X11 '
          'or configure ydotool/ydotoold for Wayland.',
        );
      }
      return;
    }

    switch (event.kind) {
      case RemoteInputEventKind.mouseMove:
        final pt = _toPoint(event.x, event.y);
        if (pt == null) return;
        if (tool == 'xdotool') {
          await _runTool(tool, ['mousemove', '${pt.$1}', '${pt.$2}']);
        } else {
          await _runTool(tool, ['mousemove_abs', '--', '${pt.$1}', '${pt.$2}']);
        }
        break;
      case RemoteInputEventKind.mouseDown:
        final btn = _xdotoolBtn(event.button);
        if (tool == 'xdotool') {
          await _runTool(tool, ['mousedown', '$btn']);
        } else {
          await _runTool(tool, ['click', '$btn']);
        }
        break;
      case RemoteInputEventKind.mouseUp:
        final btn = _xdotoolBtn(event.button);
        if (tool == 'xdotool') {
          await _runTool(tool, ['mouseup', '$btn']);
        }
        break;
      case RemoteInputEventKind.mouseScroll:
        final dy = event.scrollDeltaY ?? 0;
        if (dy != 0) {
          final btn = dy > 0 ? '5' : '4';
          if (tool == 'xdotool') {
            await _runTool(tool, ['click', btn]);
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
          await _runTool(tool, [action, keysym]);
        }
        break;
      case RemoteInputEventKind.textInput:
        final text = event.text;
        if (text == null || text.isEmpty) return;
        if (tool == 'xdotool') {
          await _runTool(tool, ['type', '--clearmodifiers', '--', text]);
        } else {
          await _runTool(tool, ['type', text]);
        }
        break;
      case RemoteInputEventKind.clipboardPaste:
        final text = event.text;
        if (text == null || text.isEmpty) return;
        await Clipboard.setData(ClipboardData(text: text));
        if (tool == 'xdotool') {
          await _runTool(tool, ['key', '--clearmodifiers', 'ctrl+v']);
        } else {
          await _runTool(tool, ['type', text]);
        }
        break;
    }
  }

  Future<void> _detectX11Geometry() async {
    try {
      final result = await Process.run('xdotool', ['getdisplaygeometry']);
      if (result.exitCode != 0) return;
      final parts = result.stdout.toString().trim().split(RegExp(r'\s+'));
      if (parts.length < 2) return;
      final width = int.tryParse(parts[0]);
      final height = int.tryParse(parts[1]);
      if (width != null && width > 0) _targetW = width;
      if (height != null && height > 0) _targetH = height;
    } catch (_) {}
  }

  Future<void> _runTool(String tool, List<String> args) async {
    try {
      final result = await Process.run(tool, args);
      if (result.exitCode != 0) {
        AppLogger.log(
          'LinuxInputInjector: $tool ${args.join(' ')} failed '
          'exit=${result.exitCode} stderr=${result.stderr}',
        );
      }
    } catch (e) {
      AppLogger.log('LinuxInputInjector: $tool ${args.join(' ')} error: $e');
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
    switch (event.keyCode) {
      case 4294967305:
        return 'BackSpace';
      case 4294967306:
        return 'Tab';
      case 4294967309:
        return 'Return';
      case 4294967323:
        return 'Escape';
      case 4294967332:
        return 'space';
      case 4294968068:
        return 'Left';
      case 4294968069:
        return 'Up';
      case 4294968070:
        return 'Right';
      case 4294968071:
        return 'Down';
      case 4294968066:
        return 'Home';
      case 4294968067:
        return 'End';
      case 4294968064:
        return 'Page_Up';
      case 4294968065:
        return 'Page_Down';
      case 4294967423:
        return 'Delete';
      case 8589934848:
      case 8589934849:
        return 'Shift_L';
      case 8589934850:
      case 8589934851:
        return 'Control_L';
      case 8589934852:
      case 8589934853:
        return 'Alt_L';
      case 8589934854:
      case 8589934855:
        return 'Super_L';
    }
    return null;
  }

  @override
  void dispose() {}
}
