import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:scn/models/remote_desktop_models.dart';
import 'package:scn/services/remote_desktop/relay_endpoints.dart';
import 'package:scn/services/remote_desktop/relay_selector.dart';
import 'package:scn/services/remote_desktop/remote_desktop_host_service.dart';
import 'package:scn/services/remote_desktop/remote_desktop_protocol.dart';
import 'package:scn/utils/logger.dart';
import 'package:scn/utils/win7_platform.dart';

export 'package:scn/services/remote_desktop/relay_endpoints.dart'
    show defaultRemoteDesktopRelayUrl;

const String defaultRemoteDesktopRelayConfigUrl =
    'https://terza.telsys.online/scn_relay_config.php';

enum RemoteDesktopRelayStatus {
  disabled,
  connecting,
  online,
  offline,
  error,
}

class _RelayLink {
  _RelayLink(this.endpoint);

  final RdRelayEndpoint endpoint;
  WebSocket? socket;
  StreamSubscription? sub;
  Timer? pingTimer;
  Timer? reconnectTimer;
  bool online = false;
  String? lastError;
  List<Map<String, dynamic>> iceServers = const [];
}

/// Host-side WAN presence: registers on every healthy relay so viewers can
/// meet on the nearest available endpoint.
class RemoteDesktopRelayService extends ChangeNotifier {
  RemoteDesktopRelayService(this._hostService);

  final RemoteDesktopHostService _hostService;

  String _deviceId = '';
  String _alias = 'SCN Device';
  RemoteDesktopSettings _settings = const RemoteDesktopSettings();
  RemoteDesktopRelayStatus _status = RemoteDesktopRelayStatus.disabled;
  String? _lastError;

  final Map<String, _RelayLink> _links = {};
  /// relaySessionId -> endpoint id (so signals go out the same socket).
  final Map<String, String> _sessionRelayId = {};

  RemoteDesktopRelayStatus get status => _status;
  String? get lastError => _lastError;
  bool get isOnline => _status == RemoteDesktopRelayStatus.online;
  String get connectionCode => _connectionCodeForId(_deviceId);

  /// Best online relay URL for UI / legacy callers.
  String get relayUrl {
    final online = _links.values.where((l) => l.online).toList();
    if (online.isEmpty) {
      return _links.values.isNotEmpty
          ? _links.values.first.endpoint.wsUrl
          : defaultRemoteDesktopRelayUrl;
    }
    // Prefer RU among online.
    online.sort((a, b) {
      if (a.endpoint.region == 'ru' && b.endpoint.region != 'ru') return -1;
      if (b.endpoint.region == 'ru' && a.endpoint.region != 'ru') return 1;
      return a.endpoint.id.compareTo(b.endpoint.id);
    });
    return online.first.endpoint.wsUrl;
  }

  List<Map<String, dynamic>> get iceServers {
    for (final link in _links.values) {
      if (link.online && link.iceServers.isNotEmpty) {
        return List.unmodifiable(link.iceServers);
      }
    }
    return const [];
  }

  /// Snapshot for UI: which relays are up.
  List<Map<String, String>> get relayStatuses {
    return _links.values
        .map((l) => {
              'id': l.endpoint.id,
              'label': l.endpoint.label,
              'url': l.endpoint.wsUrl,
              'status': l.online
                  ? 'online'
                  : (l.lastError != null ? 'error' : 'offline'),
            })
        .toList(growable: false);
  }

  void setIdentity({required String deviceId, required String alias}) {
    _deviceId = deviceId;
    _alias = alias;
  }

  void applySettings(RemoteDesktopSettings settings) {
    final wasEnabled = _settings.enabled;
    _settings = settings;
    if (!_settings.enabled) {
      AppLogger.log('RD relay: applySettings enabled=false (was=$wasEnabled)');
      stop();
      _setStatus(RemoteDesktopRelayStatus.disabled);
      return;
    }
    AppLogger.log(
        'RD relay: applySettings enabled=true was=$wasEnabled win7=$isScnWin7');
    unawaited(start());
  }

  Future<void> start({String? relayUrl}) async {
    if (_deviceId.isEmpty || !_settings.enabled) {
      AppLogger.log(
          'RD relay: start skipped (deviceIdEmpty=${_deviceId.isEmpty} enabled=${_settings.enabled})');
      return;
    }

    // Optional remote config may inject extra endpoints later; keep built-ins.
    if (!isScnWin7) {
      unawaited(_refreshConfigEndpoints());
    }

    final endpoints = [...kRdRelayEndpoints];
    if (relayUrl != null && relayUrl.isNotEmpty) {
      final exists = endpoints.any((e) => e.wsUrl == relayUrl);
      if (!exists) {
        endpoints.add(RdRelayEndpoint(
          id: 'custom',
          label: 'Custom',
          wsUrl: relayUrl,
          httpBase: relayUrl
              .replaceFirst('ws://', 'http://')
              .replaceFirst('wss://', 'https://')
              .replaceFirst(RegExp(r'/ws/?$'), ''),
          region: 'custom',
        ));
      }
    }

    AppLogger.log(
        'RD relay: start multi endpoints=${endpoints.map((e) => e.id).join(',')}');
    _setStatus(RemoteDesktopRelayStatus.connecting);

    // Best-effort probe for logs / ordering; always attempt every endpoint.
    unawaited(RdRelaySelector.probeAll());

    for (final endpoint in endpoints) {
      final link = _links.putIfAbsent(endpoint.id, () => _RelayLink(endpoint));
      if (link.socket != null && link.online) continue;
      unawaited(_connectLink(link));
    }
  }

  Future<void> _refreshConfigEndpoints() async {
    try {
      final response = await http
          .get(Uri.parse(defaultRemoteDesktopRelayConfigUrl))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      // Accept either single wsUrl or relays: [{id, wsUrl, ...}]
      final list = json['relays'];
      if (list is List) {
        for (final raw in list) {
          if (raw is! Map) continue;
          final wsUrl = raw['wsUrl']?.toString();
          if (wsUrl == null || wsUrl.isEmpty) continue;
          final id = raw['id']?.toString() ?? wsUrl;
          if (kRdRelayEndpoints.any((e) => e.id == id || e.wsUrl == wsUrl)) {
            continue;
          }
          AppLogger.log('RD relay config extra endpoint id=$id url=$wsUrl');
        }
      }
    } catch (e) {
      AppLogger.log('RD relay config fetch failed: $e');
    }
  }

  Future<void> _connectLink(_RelayLink link) async {
    if (link.socket != null) return;
    final endpoint = link.endpoint;
    AppLogger.log('RD relay: connecting ${endpoint.id} ${endpoint.wsUrl}');
    try {
      final uri = Uri.parse(endpoint.wsUrl);
      final WebSocket socket;
      if (isScnWin7 || uri.scheme == 'ws') {
        socket = await WebSocket.connect(uri.toString())
            .timeout(const Duration(seconds: 10));
      } else {
        final client = HttpClient()
          ..badCertificateCallback = (_, __, ___) => true;
        socket = await WebSocket.connect(
          uri.toString(),
          customClient: client,
        ).timeout(const Duration(seconds: 10));
      }
      link.socket = socket;
      link.lastError = null;
      socket.add(jsonEncode({
        'type': 'hello',
        'payload': {
          'role': 'rdHost',
          'deviceId': _deviceId,
          'code': connectionCode,
          'alias': _alias,
        },
      }));
      link.sub = socket.listen(
        (raw) => _onMessage(link, raw),
        onDone: () => _onLinkClosed(link),
        onError: (Object e, StackTrace st) {
          AppLogger.log('RD relay ${endpoint.id} socket error: $e\n$st');
          link.lastError = e.toString();
          _onLinkClosed(link);
        },
        cancelOnError: true,
      );
      _startPing(link);
      AppLogger.log('RD relay: ${endpoint.id} socket open, waiting welcome');
    } catch (e, st) {
      AppLogger.log('RD relay ${endpoint.id} connect failed: $e\n$st');
      link.lastError = e.toString();
      _lastError = e.toString();
      _scheduleReconnect(link);
      _refreshAggregateStatus();
    }
  }

  Future<void> stop() async {
    for (final link in _links.values.toList()) {
      link.reconnectTimer?.cancel();
      link.reconnectTimer = null;
      link.pingTimer?.cancel();
      link.pingTimer = null;
      await link.sub?.cancel();
      link.sub = null;
      final socket = link.socket;
      link.socket = null;
      link.online = false;
      try {
        await socket?.close();
      } catch (_) {}
    }
    _links.clear();
    _sessionRelayId.clear();
    if (!_settings.enabled) {
      _setStatus(RemoteDesktopRelayStatus.disabled);
    } else {
      _setStatus(RemoteDesktopRelayStatus.offline);
    }
  }

  void _onMessage(_RelayLink link, dynamic raw) {
    try {
      final message = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = message['type']?.toString();
      final payload =
          (message['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
      switch (type) {
        case 'welcome':
          link.iceServers = _parseIceServers(payload['iceServers']);
          link.online = true;
          link.lastError = null;
          _lastError = null;
          AppLogger.log(
              'RD relay: ${link.endpoint.id} online ice=${link.iceServers.length}');
          _refreshAggregateStatus();
          break;
        case 'pong':
          link.online = true;
          _refreshAggregateStatus();
          break;
        case 'rdRequest':
          unawaited(_handleRequest(link, payload));
          break;
        case 'rdSignal':
          unawaited(_handleSignal(payload));
          break;
        case 'rdBye':
          final relaySessionId = payload['relaySessionId']?.toString();
          if (relaySessionId != null) {
            _sessionRelayId.remove(relaySessionId);
            unawaited(_hostService.closeRelaySession(
              relaySessionId,
              reason: payload['reason']?.toString(),
            ));
          }
          break;
        case 'error':
          link.lastError = payload['reason']?.toString() ?? 'Relay error';
          _lastError = link.lastError;
          AppLogger.log('RD relay ${link.endpoint.id} error: ${link.lastError}');
          break;
      }
    } catch (e, st) {
      AppLogger.log('RD relay ${link.endpoint.id} message error: $e\n$st');
    }
  }

  Future<void> _handleRequest(
      _RelayLink link, Map<String, dynamic> payload) async {
    final relaySessionId = payload['relaySessionId']?.toString();
    final requestId = payload['requestId']?.toString();
    final requestJson = (payload['request'] as Map?)?.cast<String, dynamic>();
    if (relaySessionId == null || requestId == null || requestJson == null) {
      return;
    }
    _sessionRelayId[relaySessionId] = link.endpoint.id;
    final request = RemoteDesktopRequest.fromJson(requestJson);
    final iceServers = _parseIceServers(payload['iceServers']);
    final response = await _hostService.handleRelayRequest(
      relaySessionId: relaySessionId,
      request: request,
      viewerAddress: 'relay:${payload['viewerDeviceId'] ?? ''}',
      iceServers: iceServers.isEmpty ? link.iceServers : iceServers,
      sendSignal: (signal) {
        _sendOn(link, 'rdSignal', {
          'relaySessionId': relaySessionId,
          'signal': signal.toJson(),
        });
      },
    );
    _sendOn(link, 'rdResponse', {
      'requestId': requestId,
      'relaySessionId': relaySessionId,
      'response': response.toJson(),
    });
    if (response.status == RemoteDesktopRequestStatus.accepted) {
      await _hostService.startRelaySession(relaySessionId);
    } else {
      _sessionRelayId.remove(relaySessionId);
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

  void _sendOn(_RelayLink link, String type, Map<String, dynamic> payload) {
    final socket = link.socket;
    if (socket == null || socket.readyState != WebSocket.open) return;
    socket.add(jsonEncode({'type': type, 'payload': payload}));
  }

  void _startPing(_RelayLink link) {
    link.pingTimer?.cancel();
    link.pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _sendOn(link, 'ping', {'deviceId': _deviceId});
    });
  }

  void _onLinkClosed(_RelayLink link) {
    link.sub?.cancel();
    link.sub = null;
    link.pingTimer?.cancel();
    link.pingTimer = null;
    link.socket = null;
    link.online = false;
    AppLogger.log('RD relay: ${link.endpoint.id} closed');
    if (_settings.enabled) {
      _scheduleReconnect(link);
    }
    _refreshAggregateStatus();
  }

  void _scheduleReconnect(_RelayLink link) {
    if (!_settings.enabled || link.reconnectTimer != null) return;
    link.reconnectTimer = Timer(const Duration(seconds: 5), () {
      link.reconnectTimer = null;
      unawaited(_connectLink(link));
    });
  }

  void _refreshAggregateStatus() {
    if (!_settings.enabled) {
      _setStatus(RemoteDesktopRelayStatus.disabled);
      return;
    }
    final anyOnline = _links.values.any((l) => l.online);
    final anySocket = _links.values.any((l) => l.socket != null);
    if (anyOnline) {
      _setStatus(RemoteDesktopRelayStatus.online);
    } else if (anySocket) {
      _setStatus(RemoteDesktopRelayStatus.connecting);
    } else if (_links.values.any((l) => l.lastError != null)) {
      _setStatus(RemoteDesktopRelayStatus.error);
    } else {
      _setStatus(RemoteDesktopRelayStatus.offline);
    }
    notifyListeners();
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
