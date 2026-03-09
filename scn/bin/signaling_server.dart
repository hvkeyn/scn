import 'dart:io';

import 'package:scn/services/embedded_signaling_server_service.dart';

void main(List<String> args) async {
  final port = int.tryParse(Platform.environment['SCN_SIGNAL_PORT'] ?? '') ?? 8787;
  final service = EmbeddedSignalingServerService();
  await service.start(preferredPort: port);
  stdout.writeln('SCN signaling server listening on ${service.localBaseUrl}');
}
