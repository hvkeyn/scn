import 'package:flutter/material.dart';

import 'package:scn/utils/win7_webrtc.dart';

/// Win7: WebRTC PeerConnection aborts the process — do not offer RD media UI.
class Win7RemoteDesktopStub extends StatelessWidget {
  const Win7RemoteDesktopStub({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.desktop_access_disabled,
                  size: 48, color: Colors.orange.shade300),
              const SizedBox(height: 16),
              const Text(
                'Удалённый рабочий стол недоступен',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                Win7WebRtc.unsupportedMediaReason,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.4),
              ),
              const SizedBox(height: 16),
              Text(
                'Обмен файлами, чат и обнаружение устройств на Windows 7 '
                'продолжают работать.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.45),
                  height: 1.35,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
