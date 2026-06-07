import 'dart:io';

import 'package:scn/utils/logger.dart';

/// Управляет жизненным циклом привилегированного сервиса ввода SCN на Windows.
///
/// Сервис (`ScnRemoteInput`) ставится и запускается из основного (elevated)
/// приложения вызовом `scn.exe --rd-install`. Сам сервис работает под
/// LocalSystem и держит воркер (`scn.exe --rd-worker`) в активной сессии,
/// который через именованный канал принимает события ввода и проигрывает их
/// на текущем input-desktop (включая secure desktop UAC).
class InputServiceManager {
  bool _installAttempted = false;
  bool _installed = false;

  bool get isInstalled => _installed;

  /// Устанавливает и запускает сервис. Идемпотентно: повторный вызов после
  /// успеха ничего не делает. Возвращает true, если сервис (предположительно)
  /// работает.
  Future<bool> ensureRunning() async {
    if (!Platform.isWindows) return false;
    if (_installed) return true;
    _installAttempted = true;
    try {
      final exe = Platform.resolvedExecutable;
      final result = await Process.run(exe, ['--rd-install']);
      if (result.exitCode == 0) {
        _installed = true;
        AppLogger.log('InputServiceManager: service installed/started');
        return true;
      }
      AppLogger.log(
          'InputServiceManager: install failed exit=${result.exitCode} '
          'stderr=${result.stderr}');
      return false;
    } catch (e, st) {
      AppLogger.log('InputServiceManager: ensureRunning error: $e\n$st');
      return false;
    }
  }

  /// Останавливает и удаляет сервис. Вызывается при завершении сессии, чтобы не
  /// держать постоянно работающий SYSTEM-процесс.
  Future<void> stop() async {
    if (!Platform.isWindows) return;
    if (!_installAttempted) return;
    _installed = false;
    _installAttempted = false;
    try {
      final exe = Platform.resolvedExecutable;
      await Process.run(exe, ['--rd-uninstall']);
      AppLogger.log('InputServiceManager: service stopped/removed');
    } catch (e) {
      AppLogger.log('InputServiceManager: stop error: $e');
    }
  }
}
