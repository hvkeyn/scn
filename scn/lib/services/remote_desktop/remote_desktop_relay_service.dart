import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:scn/models/remote_desktop_models.dart';
import 'package:scn/services/remote_desktop/remote_desktop_host_service.dart';
import 'package:scn/services/remote_desktop/remote_desktop_protocol.dart';
import 'package:scn/utils/logger.dart';

const String defaultRemoteDesktopRelayUrl = 'ws://5.187.4.132:53319/ws';
const String defaultRemoteDesktopRelayConfigUrl =
    'https://terza.telsys.online/scn_relay_config.php';

enum RemoteDesktopRelayStatus {
  disabled,
  connecting,
  online,
  offline,
  error,
}

class RemoteDesktopRelayService extends ChangeNotifier {
  RemoteDesktopRelayService(this._hostService);

  final RemoteDesktopHostService _hostService;

  WebSocket? _socket;
  StreamSubscription? _socketSub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;

  String _deviceId = '';
  String _alias = 'SCN Device';
  RemoteDesktopSettings _settings = const RemoteDesktopSettings();
  RemoteDesktopRelayStatus _status = RemoteDesktopRelayStatus.disabled;
  String _relayUrl = defaultRemoteDesktopRelayUrl;
  String? _lastError;
  List<Map<String, dynamic>> _iceServers = const [];

  RemoteDesktopRelayStatus get status => _status;
  String get relayUrl => _relayUrl;
  String? get lastError => _lastError;
  List<Map<String, dynamic>> get iceServers => List.unmodifiable(_iceServers);
  bool get isOnline => _status == RemoteDesktopRelayStatus.online;
  String get connectionCode => _connectionCodeForId(_deviceId);

  void setIdentity({required String deviceId, required String alias}) {
    _deviceId = deviceId;
    _alias = alias;
  }

  void applySettings(RemoteDesktopSettings settings) {
    _settings = settings;
    if (!_settings.enabled) {
      stop();
      _setStatus(RemoteDesktopRelayStatus.disabled);
      return;
    }
    start();
  }

  Future<void> start({String relayUrl = defaultRemoteDesktopRelayUrl}) async {
    if (_deviceId.isEmpty || !_settings.enabled) return;
    _relayUrl = await _resolveRelayUrl(relayUrl);
    if (_socket != null ||
        _status == RemoteDesktopRelayStatus.connecting ||
        _status == RemoteDesktopRelayStatus.online) {
      return;
    }
    _setStatus(RemoteDesktopRelayStatus.connecting);
    try {
      final uri = Uri.parse(_relayUrl);
      final client = HttpClient()
        ..badCertificateCallback = (_, __, ___) => true;
      final socket = await WebSocket.connect(
        uri.toString(),
        customClient: client,
      ).timeout(const Duration(seconds: 10));
      _socket = socket;
      socket.add(jsonEncode({
        'type': 'hello',
        'payload': {
          'role': 'rdHost',
          'deviceId': _deviceId,
          'code': connectionCode,
          'alias': _alias,
        },
      }));
      _socketSub = socket.listen(
        _onMessage,
        onDone: _onClosed,
        onError: (Object e, StackTrace st) {
          AppLogger.log('RD relay host socket error: $e\n$st');
          _lastError = e.toString();
          _onClosed();
        },
        cancelOnError: true,
      );
      _startPing();
    } catch (e, st) {
      AppLogger.log('RD relay connect failed: $e\n$st');
      _lastError = e.toString();
      _setStatus(RemoteDesktopRelayStatus.error);
      _scheduleReconnect();
    }
  }

  Future<String> _resolveRelayUrl(String fallback) async {
    try {
      final response = await http
          .get(Uri.parse(defaultRemoteDesktopRelayConfigUrl))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return fallback;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final relay = (json['relay'] as Map?)?.cast<String, dynamic>();
      final wsUrl = relay?['wsUrl']?.toString();
      if (wsUrl != null && wsUrl.isNotEmpty) return wsUrl;
    } catch (e) {
      AppLogger.log('RD relay config fetch failed: $e');
    }
    return fallback;
  }

  Future<void> stop() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    await _socketSub?.cancel();
    _socketSub = null;
    final socket = _socket;
    _socket = null;
    try {
      await socket?.close();
    } catch (_) {}
    if (!_settings.enabled) {
      _setStatus(RemoteDesktopRelayStatus.disabled);
    } else {
      _setStatus(RemoteDesktopRelayStatus.offline);
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final message = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = message['type']?.toString();
      final payload =
          (message['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
      switch (type) {
        case 'welcome':
          _iceServers = _parseIceServers(payload['iceServers']);
          _lastError = null;
          _setStatus(RemoteDesktopRelayStatus.online);
          break;
        case 'pong':
          _setStatus(RemoteDesktopRelayStatus.online);
          break;
        case 'rdRequest':
          unawaited(_handleRequest(payload));
          break;
        case 'rdSignal':
          unawaited(_handleSignal(payload));
          break;
        case 'rdBye':
          final relaySessionId = payload['relaySessionId']?.toString();
          if (relaySessionId != null) {
            unawaited(_hostService.closeRelaySession(
              relaySessionId,
              reason: payload['reason']?.toString(),
            ));
          }
          break;
        case 'error':
          _lastError = payload['reason']?.toString() ?? 'Relay error';
          _setStatus(RemoteDesktopRelayStatus.error);
          break;
      }
    } catch (e, st) {
      AppLogger.log('RD relay host message error: $e\n$st');
    }
  }

  Future<void> _handleRequest(Map<String, dynamic> payload) async {
    final relaySessionId = payload['relaySessionId']?.toString();
    final requestId = payload['requestId']?.toString();
    final requestJson = (payload['request'] as Map?)?.cast<String, dynamic>();
    if (relaySessionId == null || requestId == null || requestJson == null) {
      return;
    }
    final request = RemoteDesktopRequest.fromJson(requestJson);
    final iceServers = _parseIceServers(payload['iceServers']);
    final response = await _hostService.handleRelayRequest(
      relaySessionId: relaySessionId,
      request: request,
      viewerAddress: 'relay:${payload['viewerDeviceId'] ?? ''}',
      iceServers: iceServers.isEmpty ? _iceServers : iceServers,
      sendSignal: (signal) {
        _send('rdSignal', {
          'relaySessionId': relaySessionId,
          'signal': signal.toJson(),
        });
      },
    );
    _send('rdResponse', {
      'requestId': requestId,
      'relaySessionId': relaySessionId,
      'response': response.toJson(),
    });
    if (response.status == RemoteDesktopRequestStatus.accepted) {
      await _hostService.startRelaySession(relaySessionId);
    }
  }

  Future<void> _handleSignal(Map<String, dynamic> payload) async {
    final relaySessionId = payload['relaySessionId']?.toString();
    final signalJson = (payload['signal'] as Map?)?.cast<String, dynamic>();
    if (relaySessionId == null || signalJson == null) return;
    await _hostService.handleRelaySignal(
      relaySessionId,
      RemoteDesktopSignal.fromJson(signalJson),
    );
  }

  void _send(String type, Map<String, dynamic> payload) {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) return;
    socket.add(jsonEncode({'type': type, 'payload': payload}));
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _send('ping', {'deviceId': _deviceId});
    });
  }

  void _onClosed() {
    _socketSub?.cancel();
    _socketSub = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    _socket = null;
    if (_settings.enabled) {
      _setStatus(RemoteDesktopRelayStatus.offline);
      _scheduleReconnect();
    } else {
      _setStatus(RemoteDesktopRelayStatus.disabled);
    }
  }

  void _scheduleReconnect() {
    if (!_settings.enabled || _reconnectTimer != null) return;
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      _reconnectTimer = null;
      unawaited(start(relayUrl: _relayUrl));
    });
  }

  List<Map<String, dynamic>> _parseIceServers(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((entry) => entry.cast<String, dynamic>())
        .toList(growable: false);
  }

  String _connectionCodeForId(String id) {
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return (hash % 1000000000).toString().padLeft(9, '0');
  }

  void _setStatus(RemoteDesktopRelayStatus value) {
    if (_status == value) return;
    _status = value;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
