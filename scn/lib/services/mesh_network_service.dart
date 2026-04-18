import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:scn/models/remote_peer.dart';
import 'package:scn/models/signaling_models.dart';
import 'package:scn/providers/remote_peer_provider.dart';
import 'package:scn/services/embedded_signaling_server_service.dart';
import 'package:scn/services/internet_transport_planner.dart';
import 'package:scn/services/network_diagnostics_service.dart';
import 'package:scn/services/peer_discovery_service.dart';
import 'package:scn/services/secure_channel_service.dart';
import 'package:scn/services/signaling_service.dart';
import 'package:scn/services/stun_service.dart';
import 'package:scn/services/webrtc_transport_service.dart';
import 'package:scn/utils/logger.dart';

/// Mesh Network Service
/// Manages LAN mesh peers plus WAN WebRTC sessions.
class MeshNetworkService {
  final SecureChannelService _secureChannel = SecureChannelService();
  final SignalingService _signalingService = SignalingService();
  final WebRtcTransportService _webrtcTransportService = WebRtcTransportService();
  final NetworkDiagnosticsService _networkDiagnosticsService = NetworkDiagnosticsService();
  final InternetTransportPlanner _transportPlanner = const InternetTransportPlanner();
  final EmbeddedSignalingServerService _embeddedSignaling = EmbeddedSignalingServerService();

  RemotePeerProvider? _peerProvider;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  StreamSubscription<SignalingEnvelope>? _signalingSubscription;
  Completer<bool>? _pendingConnectionCompleter;

  String _deviceId = '';
  String _deviceAlias = 'SCN Device';
  bool _isRunning = false;
  String? _fingerprint;
  String? _embeddedLocalSignalingUrl;
  String? _embeddedAdvertiseSignalingUrl;
  bool _embeddedSignalingStarted = false;

  NetworkDiagnosticsResult? _lastDiagnostics;
  SignalingSession? _hostedSession;
  String? _activeSessionId;
  String? _activePeerId;
  String? _activePeerAlias;
  PeerConnectionPath _activeConnectionPath = PeerConnectionPath.unknown;
  List<IceServerConfig> _currentIceServers = const [];
  String _connectionStage = 'idle';
  String _connectionDetails = 'WAN session is not active';
  String _signalingState = 'disconnected';
  String _iceState = 'new';
  String _dataChannelState = 'closed';
  String? _lastConnectionError;

  // Callbacks
  Function(RemotePeer peer)? onPeerConnected;
  Function(String peerId)? onPeerDisconnected;
  Function(PeerInvitation invitation)? onInvitation;
  VoidCallback? onStateChanged;

  bool get isRunning => _isRunning;
  int get port => _secureChannel.port;
  List<RemotePeer> get connectedPeers => [
        ..._secureChannel.connectedPeers,
        ...?_peerProvider?.connectedPeers.where(
          (peer) => peer.transport == PeerTransport.webRtcDataChannel,
        ),
      ];
  NetworkDiagnosticsResult? get lastDiagnostics => _lastDiagnostics;
  PeerConnectionPath get activeConnectionPath => _activeConnectionPath;
  InternetTransportPlan get currentTransportPlan =>
      _transportPlanner.planFor(_activeConnectionPath);
  SignalingSession? get hostedSession => _hostedSession;
  String get connectionStage => _connectionStage;
  String get connectionDetails => _connectionDetails;
  String get signalingState => _signalingState;
  String get iceState => _iceState;
  String get dataChannelState => _dataChannelState;
  String? get lastConnectionError => _lastConnectionError;
  bool get embeddedSignalingStarted => _embeddedSignalingStarted;
  String? get embeddedLocalSignalingUrl => _embeddedLocalSignalingUrl;
  String? get embeddedAdvertiseSignalingUrl => _embeddedAdvertiseSignalingUrl;

  void setProvider(RemotePeerProvider provider) {
    _peerProvider = provider;
    _secureChannel.setSettings(provider.settings);
  }

  void setDeviceInfo({String? deviceId, String? alias, String? fingerprint}) {
    if (deviceId != null) _deviceId = deviceId;
    if (alias != null) _deviceAlias = alias;
    if (fingerprint != null) _fingerprint = fingerprint;

    _secureChannel.setDeviceInfo(
      deviceId: deviceId,
      alias: alias,
      fingerprint: fingerprint,
    );
  }

  /// Start mesh network service
  Future<void> start() async {
    if (_isRunning) return;

    try {
      _configureCallbacks();

      _secureChannel.onMessage = _handleMessage;
      _secureChannel.onPeerConnected = _handlePeerConnected;
      _secureChannel.onPeerDisconnected = _handlePeerDisconnected;
      _secureChannel.onInvitation = _handleInvitation;

      await _embeddedSignaling.start(
        preferredPort: _peerProvider?.settings.signalingServerUrl.contains(':8787') == true
            ? 8787
            : 8787,
      );
      _embeddedSignalingStarted = true;
      _embeddedLocalSignalingUrl = _embeddedSignaling.localBaseUrl;
      _refreshAdvertisedSignalingUrl();
      _syncProviderSignalingUrl();

      await _secureChannel.start();

      _isRunning = true;
      _startPeriodicTasks();
      _reconnectSavedPeers();
      _setStage(
        'ready',
        'Embedded signaling is running at ${_embeddedLocalSignalingUrl ?? 'unknown'}',
      );

      AppLogger.log('Mesh network service started');
    } catch (e) {
      AppLogger.log('Failed to start mesh network: $e');
      _isRunning = false;
      rethrow;
    }
  }

  void _configureCallbacks() {
    _signalingSubscription ??= _signalingService.events.listen(_handleSignalingEvent);
    _webrtcTransportService.onLocalOffer = _signalingService.sendOffer;
    _webrtcTransportService.onLocalAnswer = _signalingService.sendAnswer;
    _webrtcTransportService.onLocalIceCandidate = _signalingService.sendIceCandidate;
    _webrtcTransportService.onConnectionPathChanged = (path) {
      _activeConnectionPath = path;
      _updateActivePeerDetails();
    };
    _webrtcTransportService.onConnectionStateChanged = (state) {
      _setStage('peer_connection', 'Peer connection state: $state');
      AppLogger.log('WebRTC state: $state');
    };
    _webrtcTransportService.onIceConnectionStateChanged = (state) {
      _iceState = state;
      _setStage('ice', 'ICE state: $state');
    };
    _webrtcTransportService.onDataChannelStateChanged = (state) {
      _dataChannelState = state;
      _setStage('data_channel', 'Data channel state: $state');
    };
    _webrtcTransportService.onDataMessage = (message) {
      AppLogger.log('DataChannel message: $message');
    };
  }

  void _startPeriodicTasks() {
    _reconnectTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _reconnectDisconnectedPeers();
    });

    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _sendPingToAll();
    });
  }

  Future<NetworkDiagnosticsResult> runNetworkDiagnostics({int? localPort}) async {
    final result = await _networkDiagnosticsService.analyze(
      localPort: localPort ?? _peerProvider?.settings.securePort ?? 53318,
    );
    _lastDiagnostics = result;
    _refreshAdvertisedSignalingUrl();
    _notifyStateChanged();
    return result;
  }

  Future<InviteCode?> createInternetInvite({
    String? password,
  }) async {
    final provider = _peerProvider;
    if (provider == null) return null;

    final settings = provider.settings;
    final signalingConfig = SignalingServerConfig.fromBaseUrl(
      _resolveLocalSignalingBaseUrl(settings),
    );
    final session = await _signalingService.createSession(
      config: signalingConfig,
      deviceId: _deviceId,
      deviceAlias: _deviceAlias,
    );

    _hostedSession = session;
    _activeSessionId = session.sessionId;
    _currentIceServers = _mergeIceServers(session.iceServers, settings);
    _signalingState = 'connecting';
    _setStage('signaling', 'Creating invite session ${session.sessionId}');

    await _signalingService.connect(
      config: signalingConfig,
      sessionId: session.sessionId,
      peerId: _deviceId,
      alias: _deviceAlias,
      role: 'host',
      token: session.hostToken,
    );

    return InviteCode(
      deviceId: _deviceId,
      deviceAlias: _deviceAlias,
      localPort: settings.securePort,
      password: password,
      secret: _fingerprint,
      expiresAt: session.expiresAt,
      natType: _lastDiagnostics?.natInfo?.natType ?? NatType.unknown,
      transportKind: InviteTransportKind.signalingSession,
      signalingServerUrl: _resolveAdvertisedSignalingBaseUrl(settings),
      sessionId: session.sessionId,
      inviteToken: session.joinToken,
      publicIp: _lastDiagnostics?.natInfo?.publicIp,
      publicPort: _lastDiagnostics?.natInfo?.publicPort,
    );
  }

  Future<bool> connectWithInvite(InviteCode invite, {String? password}) async {
    if (!invite.usesSignalingSession) {
      final targetPort = invite.publicPort ?? invite.localPort;
      return connectToAddress(
        address: invite.publicIp ?? '',
        port: targetPort,
        password: password ?? invite.password,
      );
    }

    final provider = _peerProvider;
    if (provider == null) return false;

    final signalingBase = invite.signalingServerUrl?.isNotEmpty == true
        ? invite.signalingServerUrl!
        : provider.settings.signalingServerUrl;
    final signalingConfig = SignalingServerConfig.fromBaseUrl(signalingBase);

    _activeSessionId = invite.sessionId;
    _activePeerAlias = invite.deviceAlias;
    _activePeerId = invite.deviceId.isNotEmpty ? invite.deviceId : null;
    _activeConnectionPath = PeerConnectionPath.unknown;
    _lastConnectionError = null;
    _completePendingConnection(false);
    _pendingConnectionCompleter = Completer<bool>();
    _setStage('signaling', 'Connecting to signaling session ${invite.sessionId}');

    await _signalingService.connect(
      config: signalingConfig,
      sessionId: invite.sessionId!,
      peerId: _deviceId,
      alias: _deviceAlias,
      role: 'joiner',
      token: invite.inviteToken!,
    );

    return _pendingConnectionCompleter!.future.timeout(
      const Duration(seconds: 25),
      onTimeout: () => false,
    );
  }

  void _reconnectSavedPeers() {
    final provider = _peerProvider;
    if (provider == null) return;

    final remotePeers = provider.remotePeers
        .where((peer) => peer.status == PeerStatus.disconnected)
        .toList();

    for (final peer in remotePeers) {
      _connectToPeer(peer);
    }
  }

  void _reconnectDisconnectedPeers() {
    final provider = _peerProvider;
    if (provider == null) return;

    final disconnectedFavorites = provider.favoritePeers
        .where((peer) => peer.status == PeerStatus.disconnected && peer.type == PeerType.remote)
        .toList();

    for (final peer in disconnectedFavorites) {
      if (peer.sessionId != null && peer.signalingServerUrl != null) {
        // Missing join token after restart means we cannot auto-rejoin safely.
        AppLogger.log('Skipping auto-reconnect for signaling peer without fresh invite: ${peer.alias}');
        continue;
      }
      _connectToPeer(peer);
    }
  }

  Future<void> _connectToPeer(RemotePeer peer) async {
    _peerProvider?.updatePeerStatus(peer.id, PeerStatus.connecting);

    final success = await _secureChannel.connectToPeer(
      address: peer.address,
      port: peer.port,
    );

    if (!success) {
      _peerProvider?.updatePeerStatus(
        peer.id,
        PeerStatus.error,
        errorMessage: 'Connection failed',
      );
    }
  }

  void _sendPingToAll() {
    _secureChannel.broadcast(SecureMessage(type: SecureMessageType.ping));
  }

  void _handleMessage(SecureMessage message, String peerId) {
    switch (message.type) {
      case SecureMessageType.peerList:
        _handlePeerList(message);
        break;
      case SecureMessageType.peerUpdate:
        _handlePeerUpdate(message);
        break;
      default:
        break;
    }
  }

  Future<void> _handleSignalingEvent(SignalingEnvelope envelope) async {
    final provider = _peerProvider;
    if (provider == null) return;

    switch (envelope.type) {
      case SignalingMessageType.hello:
        break;
      case SignalingMessageType.welcome:
        _signalingState = 'connected';
        _setStage('signaling', 'Connected to signaling server');
        final serverIce = _parseIceServers(envelope.payload['iceServers']);
        if (serverIce.isNotEmpty) {
          _currentIceServers = _mergeIceServers(serverIce, provider.settings);
        } else if (_currentIceServers.isEmpty) {
          _currentIceServers = _mergeIceServers(const [], provider.settings);
        }

        if (envelope.payload['role'] == 'joiner') {
          await _webrtcTransportService.prepareJoinerConnection(
            iceServers: _currentIceServers,
            preferRelay: provider.settings.preferRelay,
          );
        }
        break;
      case SignalingMessageType.ready:
        _activePeerId = envelope.payload['peerId'] as String? ?? _activePeerId;
        _activePeerAlias = envelope.payload['alias'] as String? ?? _activePeerAlias;
        _setStage('ready', 'Peer is ready for WebRTC negotiation');
        break;
      case SignalingMessageType.peerJoined:
        _activePeerId = envelope.payload['peerId'] as String? ?? _activePeerId;
        _activePeerAlias = envelope.payload['alias'] as String? ?? _activePeerAlias;
        _setStage('offer', 'Peer joined signaling session, creating WebRTC offer');
        await _webrtcTransportService.createHostConnection(
          iceServers: _currentIceServers,
          preferRelay: provider.settings.preferRelay,
        );
        break;
      case SignalingMessageType.offer:
        if (_currentIceServers.isEmpty) {
          _currentIceServers = _mergeIceServers(const [], provider.settings);
        }
        _setStage('offer', 'Received remote offer, creating answer');
        await _webrtcTransportService.handleOffer(envelope.payload);
        break;
      case SignalingMessageType.answer:
        _setStage('answer', 'Received remote answer');
        await _webrtcTransportService.handleAnswer(envelope.payload);
        break;
      case SignalingMessageType.iceCandidate:
        _setStage('ice', 'Received ICE candidate');
        await _webrtcTransportService.addRemoteCandidate(envelope.payload);
        break;
      case SignalingMessageType.peerLeft:
      case SignalingMessageType.bye:
        final peerId = envelope.payload['peerId'] as String? ?? _activePeerId;
        if (peerId != null) {
          _handlePeerDisconnected(peerId);
        }
        break;
      case SignalingMessageType.error:
        _lastConnectionError = envelope.payload.toString();
        _completePendingConnection(false);
        AppLogger.log('Signaling error: ${envelope.payload}');
        _setStage('error', 'Signaling error: ${envelope.payload}');
        break;
      case SignalingMessageType.ping:
        _signalingService.send(
          const SignalingEnvelope(type: SignalingMessageType.pong),
        );
        break;
      case SignalingMessageType.pong:
        break;
    }
  }

  void _handlePeerList(SecureMessage message) {
    final provider = _peerProvider;
    if (provider == null || !provider.settings.meshEnabled) return;

    final payload = message.payload ?? {};
    final discoveredPeer = payload['discoveredPeer'] as Map<String, dynamic>?;

    if (discoveredPeer != null) {
      final peer = RemotePeer.fromJson(discoveredPeer);

      if (peer.id != _deviceId) {
        provider.addPeer(peer);
        if (peer.status == PeerStatus.disconnected) {
          AppLogger.log('Discovered peer via mesh: ${peer.alias}');
        }
      }
    }
  }

  void _handlePeerUpdate(SecureMessage message) {
    final payload = message.payload ?? {};
    final peerId = payload['peerId'] as String?;
    final status = payload['status'] as String?;

    if (peerId != null && status != null) {
      final peerStatus = PeerStatus.values.firstWhere(
        (value) => value.name == status,
        orElse: () => PeerStatus.disconnected,
      );
      _peerProvider?.updatePeerStatus(peerId, peerStatus);
    }
  }

  void _handlePeerConnected(RemotePeer peer) {
    _peerProvider?.addPeer(peer);
    _peerProvider?.updatePeerStatus(peer.id, PeerStatus.connected);
    onPeerConnected?.call(peer);

    AppLogger.log('Peer connected: ${peer.alias}');
  }

  void _handlePeerDisconnected(String peerId) {
    _peerProvider?.updatePeerStatus(peerId, PeerStatus.disconnected);
    onPeerDisconnected?.call(peerId);

    if (_activePeerId == peerId) {
      _activePeerId = null;
      _activePeerAlias = null;
      _activeConnectionPath = PeerConnectionPath.unknown;
    }

    AppLogger.log('Peer disconnected: $peerId');
  }

  void _handleInvitation(PeerInvitation invitation) {
    _peerProvider?.addInvitation(invitation);
    onInvitation?.call(invitation);

    AppLogger.log('Received invitation from: ${invitation.fromAlias}');
  }

  /// Connect to a remote peer by address
  Future<bool> connectToAddress({
    required String address,
    int port = 53318,
    String? password,
  }) async {
    if (address.trim().isEmpty) return false;

    try {
      final success = await _secureChannel.connectToPeer(
        address: address,
        port: port,
        password: password,
      );
      if (success) {
        _activeConnectionPath = PeerConnectionPath.legacyDirect;
      }
      return success;
    } catch (e) {
      debugPrint('Failed to connect to $address:$port: $e');
      return false;
    }
  }

  /// Disconnect from a specific peer
  void disconnectPeer(String peerId) {
    RemotePeer? peer;
    final provider = _peerProvider;
    if (provider != null) {
      for (final entry in provider.peers) {
        if (entry.id == peerId) {
          peer = entry;
          break;
        }
      }
    }

    if (peer != null && peer.transport == PeerTransport.webRtcDataChannel) {
      _signalingService.sendBye(reason: 'local_disconnect');
      _webrtcTransportService.close();
      _signalingService.disconnect();
      _completePendingConnection(false);
      _setStage('disconnect', 'WAN peer disconnected locally');
    }

    _secureChannel.disconnectPeer(peerId);
    _peerProvider?.updatePeerStatus(peerId, PeerStatus.disconnected);
  }

  /// Accept an invitation
  Future<bool> acceptInvitation(PeerInvitation invitation, {String? password}) async {
    _peerProvider?.removeInvitation(invitation.id);
    return _secureChannel.acceptInvitation(invitation, password: password);
  }

  /// Reject an invitation
  void rejectInvitation(PeerInvitation invitation) {
    _secureChannel.rejectInvitation(invitation);
    _peerProvider?.removeInvitation(invitation.id);
  }

  /// Send data to a specific peer
  void sendToPeer(String peerId, Map<String, dynamic> data) {
    RemotePeer? webRtcPeer;
    final provider = _peerProvider;
    if (provider != null) {
      for (final peer in provider.peers) {
        if (peer.id == peerId) {
          webRtcPeer = peer;
          break;
        }
      }
    }
    if (webRtcPeer != null && webRtcPeer.transport == PeerTransport.webRtcDataChannel) {
      _webrtcTransportService.sendJson(data);
      return;
    }

    _secureChannel.sendToPeer(
      peerId,
      SecureMessage(
        type: SecureMessageType.data,
        senderId: _deviceId,
        senderAlias: _deviceAlias,
        payload: data,
      ),
    );
  }

  /// Broadcast data to all connected peers
  void broadcast(Map<String, dynamic> data) {
    _secureChannel.broadcast(
      SecureMessage(
        type: SecureMessageType.data,
        senderId: _deviceId,
        senderAlias: _deviceAlias,
        payload: data,
      ),
    );
  }

  /// Update settings
  void updateSettings(NetworkSettings settings) {
    _secureChannel.setSettings(settings);
    _refreshAdvertisedSignalingUrl();
    _notifyStateChanged();
  }

  void _updateActivePeerDetails() {
    final peerId = _activePeerId ?? _activeSessionId;
    if (peerId == null) return;

    final provider = _peerProvider;
    if (provider == null) return;

    RemotePeer? existing;
    for (final peer in provider.peers) {
      if (peer.id == peerId) {
        existing = peer;
        break;
      }
    }
    final settings = provider.settings;
    final uri = Uri.tryParse(settings.signalingServerUrl);
    final port = uri?.port == 0 ? 443 : (uri?.port ?? 443);

    final peer = (existing ??
            RemotePeer(
              id: peerId,
              alias: _activePeerAlias ?? 'Internet peer',
              address: uri?.host ?? 'signaling',
              port: port,
              type: PeerType.remote,
            ))
        .copyWith(
      alias: _activePeerAlias ?? existing?.alias ?? 'Internet peer',
      status: PeerStatus.connected,
      transport: PeerTransport.webRtcDataChannel,
      connectionPath: _activeConnectionPath,
      relayRequired: _activeConnectionPath == PeerConnectionPath.relayed,
      sessionId: _activeSessionId,
      signalingServerUrl: settings.signalingServerUrl,
      lastSeen: DateTime.now(),
      errorMessage: null,
    );

    provider.addPeer(peer);
    onPeerConnected?.call(peer);
    _completePendingConnection(true);
    _setStage(
      'connected',
      'Connected via ${peer.transport.name} using ${peer.connectionPath.name}',
    );
  }

  List<IceServerConfig> _mergeIceServers(
    List<IceServerConfig> sessionIceServers,
    NetworkSettings settings,
  ) {
    final merged = <IceServerConfig>[
      ...sessionIceServers,
      if (settings.stunServers.isNotEmpty)
        IceServerConfig(urls: settings.stunServers),
      if (settings.turnServers.isNotEmpty)
        IceServerConfig(urls: settings.turnServers),
    ];

    final seen = <String>{};
    return merged.where((server) {
      final key = '${server.urls.join(',')}|${server.username}|${server.credential}';
      return seen.add(key);
    }).toList();
  }

  List<IceServerConfig> _parseIceServers(dynamic rawIceServers) {
    if (rawIceServers is! List) return const [];
    return rawIceServers
        .whereType<Map<String, dynamic>>()
        .map(IceServerConfig.fromJson)
        .toList();
  }

  void _completePendingConnection(bool value) {
    final completer = _pendingConnectionCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(value);
    }
  }

  String _resolveLocalSignalingBaseUrl(NetworkSettings settings) {
    final configured = settings.signalingServerUrl.trim();
    if (_isLocalHostUrl(configured) && _embeddedLocalSignalingUrl != null) {
      return _embeddedLocalSignalingUrl!;
    }
    return configured;
  }

  String _resolveAdvertisedSignalingBaseUrl(NetworkSettings settings) {
    final configured = settings.signalingServerUrl.trim();
    if (_isLocalHostUrl(configured)) {
      return _embeddedAdvertiseSignalingUrl ?? configured;
    }
    return configured;
  }

  bool _isLocalHostUrl(String value) {
    final uri = Uri.tryParse(value);
    final host = uri?.host.toLowerCase();
    return host == '127.0.0.1' || host == 'localhost';
  }

  void _refreshAdvertisedSignalingUrl() {
    final localUrl = _embeddedLocalSignalingUrl;
    if (localUrl == null) return;

    final localUri = Uri.parse(localUrl);
    final publicIp = _lastDiagnostics?.natInfo?.publicIp;
    if (publicIp != null && publicIp.isNotEmpty) {
      _embeddedAdvertiseSignalingUrl = Uri(
        scheme: localUri.scheme,
        host: publicIp,
        port: localUri.port,
      ).toString();
      return;
    }

    _embeddedAdvertiseSignalingUrl = localUrl;
  }

  void _syncProviderSignalingUrl() {
    final provider = _peerProvider;
    final localUrl = _embeddedLocalSignalingUrl;
    if (provider == null || localUrl == null) return;
    if (_isLocalHostUrl(provider.settings.signalingServerUrl) &&
        provider.settings.signalingServerUrl != localUrl) {
      provider.setSignalingServerUrl(localUrl);
    }
  }

  void _setStage(String stage, String details) {
    _connectionStage = stage;
    _connectionDetails = details;
    _notifyStateChanged();
  }

  void _notifyStateChanged() {
    onStateChanged?.call();
  }

  /// Stop server and all WAN transports.
  Future<void> stop() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    _pingTimer?.cancel();
    _pingTimer = null;

    await _webrtcTransportService.close();
    await _signalingService.disconnect();
    await _embeddedSignaling.stop();
    await _secureChannel.stop();
    await _signalingSubscription?.cancel();
    _signalingSubscription = null;
    _isRunning = false;
    _embeddedSignalingStarted = false;
    _embeddedLocalSignalingUrl = null;
    _embeddedAdvertiseSignalingUrl = null;
    _setStage('stopped', 'Mesh and signaling services stopped');

    debugPrint('Mesh network service stopped');
  }
}

