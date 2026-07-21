import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:scn/utils/logger.dart';
import 'package:scn/utils/win7_platform.dart';

/// On Win7, flutter_webrtc is not registered at startup (crashes).
/// Call [ensureEnabled] before any WebRTC API.
///
/// PeerConnection::Create inside libwebrtc.dll aborts the process on Win7
/// (builds 206 hang / 207–208 WER). WebRTC media is unsupported; use GDI
/// JPEG frame transport for RD host instead (build 210+).
class Win7WebRtc {
  Win7WebRtc._();

  static const _channel = MethodChannel('scn/win7_rd');
  static Future<void>? _pending;
  static bool _enabled = false;
  static bool _gpuHooksApplied = false;

  /// Human-readable reason shown when WebRTC Create is attempted on Win7.
  static const unsupportedMediaReason =
      'WebRTC createPeerConnection на Windows 7 недоступен (libwebrtc abort). '
      'Удалённый стол на Win7 работает через GDI JPEG frames.';

  static bool get isEnabled => _enabled || !isScnWin7;

  /// False on Win7 — calling [createPeerConnection] aborts the process.
  static bool get isMediaSupported => !isScnWin7;

  /// Registers native FlutterWebRTC plugin on Win7. No-op elsewhere.
  /// Does not prove Create works — see [isMediaSupported].
  static Future<void> ensureEnabled() {
    if (!isScnWin7 || _enabled) {
      return Future.value();
    }
    return _pending ??= _enableOnce();
  }

  static Future<void> _enableOnce() async {
    AppLogger.log('Win7 WebRTC: enableWebRtc requested');
    try {
      final ok = await _channel.invokeMethod<bool>('enableWebRtc');
      if (ok != true) {
        throw StateError('enableWebRtc returned $ok');
      }
      _enabled = true;
      AppLogger.log('Win7 WebRTC: plugin registered (media still unsupported)');
    } catch (e, st) {
      _pending = null;
      AppLogger.log('Win7 WebRTC: enable failed: $e\n$st');
      rethrow;
    }
  }

  /// Block DXGI/D3D11 on libwebrtc before screen capture (Win10+ path only).
  static Future<void> applyGpuHooksForCapture() async {
    if (!isScnWin7 || _gpuHooksApplied) {
      return;
    }
    await ensureEnabled();
    AppLogger.log('Win7 WebRTC: applyGpuHooksForCapture…');
    try {
      await _channel.invokeMethod<bool>('applyWebRtcGpuHooks');
      _gpuHooksApplied = true;
      AppLogger.log('Win7 WebRTC: GPU hooks applied for capture');
    } catch (e, st) {
      AppLogger.log('Win7 WebRTC: applyGpuHooks failed: $e\n$st');
      rethrow;
    }
  }
}

/// Summarize ICE URLs for logs (no credentials).
String summarizeIceServers(List<Map<String, dynamic>> iceServers) {
  final urls = <String>[];
  for (final server in iceServers) {
    final raw = server['urls'] ?? server['url'];
    if (raw is String) {
      urls.add(raw);
    } else if (raw is List) {
      for (final item in raw) {
        urls.add(item.toString());
      }
    }
  }
  return 'count=${iceServers.length} urls=[${urls.join(', ')}]';
}

/// Create an RTCPeerConnection with Win7-safe defaults.
///
/// On Win7 throws [UnsupportedError] — never calls native Create (process abort).
Future<RTCPeerConnection> createScnPeerConnection({
  required List<Map<String, dynamic>> iceServers,
  bool offerToReceiveAudio = false,
  bool offerToReceiveVideo = false,
  Duration timeout = const Duration(seconds: 25),
}) async {
  if (isScnWin7) {
    AppLogger.log('WebRTC: refused createPeerConnection on Win7 (media unsupported)');
    throw UnsupportedError(Win7WebRtc.unsupportedMediaReason);
  }

  AppLogger.log(
      'WebRTC: createPeerConnection begin win7=false '
      '${summarizeIceServers(iceServers)}');

  await WebRTC.initialize();
  AppLogger.log('WebRTC: initialize ok');

  final constraints = <String, dynamic>{
    'mandatory': {
      'OfferToReceiveAudio': offerToReceiveAudio,
      'OfferToReceiveVideo': offerToReceiveVideo,
    },
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
    ],
  };

  final pc = await createPeerConnection({
    'iceServers': iceServers,
    'sdpSemantics': 'unified-plan',
  }, constraints).timeout(
    timeout,
    onTimeout: () => throw TimeoutException(
      'createPeerConnection timed out (>${timeout.inSeconds}s)',
    ),
  );

  AppLogger.log('WebRTC: createPeerConnection ok');
  return pc;
}
