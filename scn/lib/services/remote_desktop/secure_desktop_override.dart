import 'dart:async';
import 'dart:io';

import 'package:scn/utils/logger.dart';

/// Управляет временным отключением UAC Secure Desktop на Windows,
/// чтобы viewer мог взаимодействовать с UAC-окном.
///
/// Без UIAccess+code signing никакое приложение не может посылать
/// мышь/клавиатуру в защищённый рабочий стол UAC. Единственный
/// практичный workaround — выключить `PromptOnSecureDesktop` в
/// `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System`,
/// тогда UAC показывается на обычном рабочем столе, и его можно
/// автоматизировать удалённо. Это снижает безопасность, поэтому
/// делается только пока активна RD-сессия и только если пользователь
/// явно включил опцию.
class SecureDesktopOverride {
  static const String _keyPath =
      r'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System';
  static const String _valueName = 'PromptOnSecureDesktop';

  /// Сохранённое исходное значение реестра (если присутствовало).
  /// `-1` = значение отсутствовало.
  int? _originalValue;
  bool _engaged = false;

  bool get isEngaged => _engaged;

  /// Включает override: запоминает старое значение и выставляет 0.
  /// Возвращает true, если override успешно применён.
  Future<bool> engage() async {
    if (!Platform.isWindows) return false;
    if (_engaged) return true;
    try {
      _originalValue = await _readCurrentValue();
      AppLogger.log(
          'SecureDesktopOverride.engage: original PromptOnSecureDesktop=$_originalValue');
      if (_originalValue == 0) {
        _engaged = true;
        return true;
      }
      final ok = await _writeValue(0);
      if (ok) {
        _engaged = true;
        AppLogger.log(
            'SecureDesktopOverride.engage: PromptOnSecureDesktop set to 0');
      } else {
        AppLogger.log(
            'SecureDesktopOverride.engage: failed to write registry; viewer will not be able to interact with UAC');
      }
      return ok;
    } catch (e, st) {
      AppLogger.log('SecureDesktopOverride.engage failed: $e\n$st');
      return false;
    }
  }

  /// Восстанавливает исходное значение реестра.
  Future<void> disengage() async {
    if (!Platform.isWindows) return;
    if (!_engaged) return;
    _engaged = false;
    try {
      final original = _originalValue;
      if (original == null || original < 0) {
        await _deleteValue();
        AppLogger.log(
            'SecureDesktopOverride.disengage: removed PromptOnSecureDesktop (was absent)');
      } else {
        await _writeValue(original);
        AppLogger.log(
            'SecureDesktopOverride.disengage: restored PromptOnSecureDesktop=$original');
      }
    } catch (e, st) {
      AppLogger.log('SecureDesktopOverride.disengage failed: $e\n$st');
    } finally {
      _originalValue = null;
    }
  }

  Future<int?> _readCurrentValue() async {
    try {
      final res = await Process.run(
        'reg.exe',
        ['query', _keyPath, '/v', _valueName],
        runInShell: false,
      );
      if (res.exitCode != 0) {
        return -1;
      }
      final out = (res.stdout?.toString() ?? '');
      final match =
          RegExp(r'REG_DWORD\s+0x([0-9a-fA-F]+)').firstMatch(out);
      if (match == null) return -1;
      return int.parse(match.group(1)!, radix: 16);
    } catch (_) {
      return -1;
    }
  }

  Future<bool> _writeValue(int value) async {
    try {
      final res = await Process.run(
        'reg.exe',
        [
          'add',
          _keyPath,
          '/v',
          _valueName,
          '/t',
          'REG_DWORD',
          '/d',
          value.toString(),
          '/f',
        ],
        runInShell: false,
      );
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _deleteValue() async {
    try {
      final res = await Process.run(
        'reg.exe',
        ['delete', _keyPath, '/v', _valueName, '/f'],
        runInShell: false,
      );
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
