import 'dart:io';

import 'package:scn/models/remote_desktop_models.dart';
import 'package:scn/providers/remote_peer_provider.dart';
import 'package:scn/utils/logger.dart';
import 'package:scn/utils/win7_platform.dart';

/// Force GDI JPEG frame RD transport (Win7 or local smoke on Win10).
bool get useRdFramesTransport =>
    isScnWin7 || Platform.environment['SCN_RD_FRAMES'] == '1';

String get rdTestPassword {
  final raw = Platform.environment['SCN_RD_TEST_PASSWORD']?.trim();
  if (raw != null && raw.isNotEmpty) return raw;
  return 'test1234';
}

/// `host:port` for viewer auto-connect smoke (optional).
String? get rdTestConnectTarget {
  final raw = Platform.environment['SCN_RD_TEST_CONNECT']?.trim();
  if (raw == null || raw.isEmpty) return null;
  return raw;
}

/// Auto-enable password-only RD host for LAN/WAN smoke tests.
///
/// Env:
///   SCN_RD_TEST_HOST=1
///   SCN_RD_TEST_PASSWORD=test1234 (optional)
Future<void> applyRdTestHostOverrides(RemotePeerProvider peers) async {
  if (Platform.environment['SCN_RD_TEST_HOST'] != '1') {
    return;
  }
  final password = rdTestPassword;
  await peers.updateRemoteDesktopSettings(
    RemoteDesktopSettings(
      enabled: true,
      accessMode: RemoteDesktopAccessMode.passwordOnly,
      password: password,
      shareAudio: false,
      viewOnlyByDefault: false,
      defaultFps: 6,
      defaultVideoBitrateKbps: 1500,
      preferredVideoCodec: 'jpeg',
    ),
  );
  AppLogger.log(
      'RD test host ON (password set, frames=$useRdFramesTransport)');
}
