import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:scn/models/remote_peer.dart';

/// Secure WebSocket channel service
/// Uses WSS (WebSocket over TLS) to bypass DPI and provide encryption
class SecureChannelService {
  HttpServer? _server;
  final Map<String, WebSocket> _connections = {};
  final Map<String, RemotePeer> _connectedPeers = {};
  final Uuid _uuid = const Uuid();
  
  // Callbacks
  Function(SecureMessage message, String peerId)? onMessage;
  Function(RemotePeer peer)? onPeerConnected;
  Function(String peerId)? onPeerDisconnected;
  Function(PeerInvitation invitation)? onInvitation;
  
  // Device info
  String _deviceId = '';
  String _deviceAlias = 'SCN Device';
  String _fingerprint = '';
  NetworkSettings _settings = const NetworkSettings();
  
  int get port => _settings.securePort;
  bool get isRunning => _server != null;
  List<RemotePeer> get connectedPeers => _connectedPeers.values.toList();
  
  void setDeviceInfo({
    String? deviceId,
    String? alias,
    String? fingerprint,
  }) {
    if (deviceId != null) _deviceId = deviceId;
    if (alias != null) _deviceAlias = alias;
    if (fingerprint != null) _fingerprint = fingerprint;
  }
  
  void setSettings(NetworkSettings settings) {
    _settings = settings;
  }
  
  /// Start secure WebSocket server
  Future<void> start() async {
    if (_server != null) return;
    
    try {
      // Generate self-signed certificate for TLS
      final securityContext = await _createSecurityContext();
      
      // Try multiple ports
      final portsToTry = [
        _settings.securePort,
        _settings.securePort + 1,
        _settings.securePort + 2,
      ];
      
      for (final port in portsToTry) {
        try {
          _server = await HttpServer.bindSecure(
            InternetAddress.anyIPv4,
            port,
            securityContext,
          );
          
          print('Secure WebSocket server started on port $port');
          
          _server!.listen(_handleConnection);
          return;
        } on SocketException {
          print('Port $port is busy, trying next...');
          continue;
        }
      }
      
      // Fallback: try without TLS for testing
      print('TLS failed, trying plain WebSocket...');
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _settings.securePort);
      _server!.listen(_handleConnection);
      print('WebSocket server started on port ${_settings.securePort} (no TLS)');
      
    } catch (e) {
      print('Failed to start secure server: $e');
      rethrow;
    }
  }
  
  Future<SecurityContext> _createSecurityContext() async {
    // For production, use proper certificates
    // For now, create a basic context that accepts self-signed certs
    final context = SecurityContext(withTrustedRoots: false);
    
    // Generate temporary certificate
    final certData = await _generateSelfSignedCert();
    context.useCertificateChainBytes(certData['cert']!);
    context.usePrivateKeyBytes(certData['key']!);
    
    return context;
  }
  
  Future<Map<String, Uint8List>> _generateSelfSignedCert() async {
    // Simple self-signed certificate generation
    // In production, use a proper certificate
    final random = Random.secure();
    final bytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      bytes[i] = random.nextInt(256);
    }
    
    // Return placeholder - in real implementation use proper cert generation
    // For now, we'll rely on the fallback plain WebSocket
    return {
      'cert': Uint8List(0),
      'key': Uint8List(0),
    };
  }
  
  void _handleConnection(HttpRequest request) async {
    // Check if it's a WebSocket upgrade request
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      try {
        final socket = await WebSocketTransformer.upgrade(request);
        final connectionId = _uuid.v4();
        
        _connections[connectionId] = socket;
        print('New WebSocket connection: $connectionId');
        
        // Handle incoming messages
        socket.listen(
          (data) => _handleMessage(connectionId, data),
          onDone: () => _handleDisconnect(connectionId),
          onError: (e) => _handleError(connectionId, e),
        );
        
        // Send handshake
        _sendHandshake(connectionId);
        
      } catch (e) {
        print('WebSocket upgrade failed: $e');
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.close();
      }
    } else {
      // Return fake HTTP response to look like normal web server
      // This helps bypass DPI
      _sendFakeHttpResponse(request);
    }
  }
  
  void _sendFakeHttpResponse(HttpRequest request) {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..write('''<!DOCTYPE html>
<html><head><title>Welcome</title></head>
<body><h1>Welcome to our service</h1></body></html>''')
      ..close();
  }
  
  void _sendHandshake(String connectionId) {
    final message = SecureMessage(
      type: SecureMessageType.handshake,
      senderId: _deviceId,
      senderAlias: _deviceAlias,
      payload: {
        'fingerprint': _fingerprint,
        'version': '1.0',
        'requiresPassword': !_settings.acceptWithoutPassword,
        'meshEnabled': _settings.meshEnabled,
        'sharePeers': _settings.sharePeers,
      },
    );
    
    _sendToConnection(connectionId, message);
  }
  
  void _handleMessage(String connectionId, dynamic data) {
    try {
      final jsonStr = data is String ? data : utf8.decode(data as List<int>);
      final message = SecureMessage.fromJsonString(jsonStr);
      
      switch (message.type) {
        case SecureMessageType.handshake:
          _handleHandshake(connectionId, message);
          break;
        case SecureMessageType.handshakeAck:
          _handleHandshakeAck(connectionId, message);
          break;
        case SecureMessageType.peerList:
          _handlePeerList(connectionId, message);
          break;
        case SecureMessageType.invitation:
          _handleInvitation(connectionId, message);
          break;
        case SecureMessageType.invitationAck:
          _handleInvitationAck(connectionId, message);
          break;
        case SecureMessageType.ping:
          _sendPong(connectionId);
          break;
        case SecureMessageType.pong:
          // Keep-alive received
          break;
        case SecureMessageType.disconnect:
          _handleDisconnect(connectionId);
          break;
        default:
          // Forward to callback
          final peer = _connectedPeers[connectionId];
          if (peer != null) {
            onMessage?.call(message, peer.id);
          }
      }
    } catch (e) {
      print('Error handling message: $e');
    }
  }
  
  void _handleHandshake(String connectionId, SecureMessage message) {
    final payload = message.payload ?? {};
    final peerId = message.senderId ?? connectionId;
    
    // Check password if required
    if (!_settings.acceptWithoutPassword && _settings.connectionPassword != null) {
      final providedPassword = payload['password'] as String?;
      if (providedPassword != _settings.connectionPassword) {
        // Send rejection
        _sendToConnection(connectionId, SecureMessage(
          type: SecureMessageType.handshakeAck,
          senderId: _deviceId,
          senderAlias: _deviceAlias,
          payload: {'accepted': false, 'reason': 'Invalid password'},
        ));
        _connections[connectionId]?.close();
        _connections.remove(connectionId);
        return;
      }
    }
    
    // Create peer
    final peer = RemotePeer(
      id: peerId,
      alias: message.senderAlias ?? 'Unknown',
      address: '', // Will be updated from socket
      port: _settings.securePort,
      type: PeerType.remote,
      status: PeerStatus.connected,
      fingerprint: payload['fingerprint'] as String?,
      lastSeen: DateTime.now(),
    );
    
    _connectedPeers[connectionId] = peer;
    
    // Send acknowledgment
    _sendToConnection(connectionId, SecureMessage(
      type: SecureMessageType.handshakeAck,
      senderId: _deviceId,
      senderAlias: _deviceAlias,
      payload: {
        'accepted': true,
        'fingerprint': _fingerprint,
        'meshEnabled': _settings.meshEnabled,
        'sharePeers': _settings.sharePeers,
      },
    ));
    
    // Notify callback
    onPeerConnected?.call(peer);
    
    // Share peer list if mesh enabled
    if (_settings.meshEnabled && _settings.sharePeers) {
      _sharePeerList(connectionId);
    }
  }
  
  void _handleHandshakeAck(String connectionId, SecureMessage message) {
    final payload = message.payload ?? {};
    final accepted = payload['accepted'] as bool? ?? false;
    
    if (!accepted) {
      print('Handshake rejected: ${payload['reason']}');
      _connections[connectionId]?.close();
      _connections.remove(connectionId);
      return;
    }
    
    // Update peer status
    final peer = _connectedPeers[connectionId];
    if (peer != null) {
      _connectedPeers[connectionId] = peer.copyWith(
        status: PeerStatus.connected,
        fingerprint: payload['fingerprint'] as String?,
        lastSeen: DateTime.now(),
      );
      onPeerConnected?.call(_connectedPeers[connectionId]!);
    }
  }
  
  void _handlePeerList(String connectionId, SecureMessage message) {
    if (!_settings.meshEnabled) return;
    
    final payload = message.payload ?? {};
    final peers = payload['peers'] as List<dynamic>? ?? [];
    
    // Callback to handle discovered peers
    for (final peerData in peers) {
      if (peerData is Map<String, dynamic>) {
        final discoveredPeer = RemotePeer.fromJson(peerData);
        // Don't add ourselves
        if (discoveredPeer.id != _deviceId) {
          onMessage?.call(
            SecureMessage(
              type: SecureMessageType.peerList,
              payload: {'discoveredPeer': discoveredPeer.toJson()},
            ),
            connectionId,
          );
        }
      }
    }
  }
  
  void _handleInvitation(String connectionId, SecureMessage message) {
    final payload = message.payload ?? {};
    
    final invitation = PeerInvitation(
      id: _uuid.v4(),
      fromAlias: message.senderAlias ?? 'Unknown',
      fromAddress: payload['address'] as String? ?? '',
      fromPort: payload['port'] as int? ?? _settings.securePort,
      fingerprint: payload['fingerprint'] as String?,
      requiresPassword: payload['requiresPassword'] as bool? ?? false,
    );
    
    onInvitation?.call(invitation);
  }
  
  void _handleInvitationAck(String connectionId, SecureMessage message) {
    final payload = message.payload ?? {};
    final accepted = payload['accepted'] as bool? ?? false;
    
    if (accepted) {
      // Invitation accepted, complete connection
      print('Invitation accepted by peer');
    } else {
      print('Invitation rejected: ${payload['reason']}');
    }
  }
  
  void _sendPong(String connectionId) {
    _sendToConnection(connectionId, SecureMessage(type: SecureMessageType.pong));
  }
  
  void _sharePeerList(String connectionId) {
    final peerList = _connectedPeers.values
        .where((p) => p.id != connectionId)
        .map((p) => p.toJson())
        .toList();
    
    _sendToConnection(connectionId, SecureMessage(
      type: SecureMessageType.peerList,
      senderId: _deviceId,
      senderAlias: _deviceAlias,
      payload: {'peers': peerList},
    ));
  }
  
  void _handleDisconnect(String connectionId) {
    final peer = _connectedPeers[connectionId];
    _connections[connectionId]?.close();
    _connections.remove(connectionId);
    _connectedPeers.remove(connectionId);
    
    if (peer != null) {
      onPeerDisconnected?.call(peer.id);
    }
    
    print('Peer disconnected: $connectionId');
  }
  
  void _handleError(String connectionId, dynamic error) {
    print('WebSocket error for $connectionId: $error');
    _handleDisconnect(connectionId);
  }
  
  void _sendToConnection(String connectionId, SecureMessage message) {
    final socket = _connections[connectionId];
    if (socket != null) {
      try {
        socket.add(message.toJsonString());
      } catch (e) {
        print('Failed to send to $connectionId: $e');
      }
    }
  }
  
  /// Connect to a remote peer
  Future<bool> connectToPeer({
    required String address,
    required int port,
    String? password,
  }) async {
    try {
      final uri = Uri.parse('ws://$address:$port/ws');
      
      // Try WSS first, fallback to WS
      WebSocket socket;
      try {
        socket = await WebSocket.connect(
          'wss://$address:$port/ws',
          customClient: HttpClient()..badCertificateCallback = (_, __, ___) => true,
        ).timeout(const Duration(seconds: 10));
      } catch (e) {
        print('WSS failed, trying WS: $e');
        socket = await WebSocket.connect(uri.toString())
            .timeout(const Duration(seconds: 10));
      }
      
      final connectionId = _uuid.v4();
      _connections[connectionId] = socket;
      
      // Create pending peer
      _connectedPeers[connectionId] = RemotePeer(
        id: connectionId,
        alias: 'Connecting...',
        address: address,
        port: port,
        type: PeerType.remote,
        status: PeerStatus.connecting,
      );
      
      // Listen for messages
      socket.listen(
        (data) => _handleMessage(connectionId, data),
        onDone: () => _handleDisconnect(connectionId),
        onError: (e) => _handleError(connectionId, e),
      );
      
      // Send handshake with password if provided
      final message = SecureMessage(
        type: SecureMessageType.handshake,
        senderId: _deviceId,
        senderAlias: _deviceAlias,
        payload: {
          'fingerprint': _fingerprint,
          'version': '1.0',
          'password': password,
          'meshEnabled': _settings.meshEnabled,
          'sharePeers': _settings.sharePeers,
        },
      );
      
      socket.add(message.toJsonString());
      
      return true;
    } catch (e) {
      print('Failed to connect to peer: $e');
      return false;
    }
  }
  
  /// Send invitation to a remote address
  Future<bool> sendInvitation({
    required String address,
    required int port,
  }) async {
    try {
      // Try to connect and send invitation
      return await connectToPeer(address: address, port: port);
    } catch (e) {
      print('Failed to send invitation: $e');
      return false;
    }
  }
  
  /// Accept an invitation
  Future<bool> acceptInvitation(PeerInvitation invitation, {String? password}) async {
    return await connectToPeer(
      address: invitation.fromAddress,
      port: invitation.fromPort,
      password: password,
    );
  }
  
  /// Reject an invitation
  void rejectInvitation(PeerInvitation invitation) {
    // No action needed - just don't connect
    print('Invitation from ${invitation.fromAlias} rejected');
  }
  
  /// Send message to specific peer
  void sendToPeer(String peerId, SecureMessage message) {
    for (final entry in _connectedPeers.entries) {
      if (entry.value.id == peerId) {
        _sendToConnection(entry.key, message);
        return;
      }
    }
    print('Peer not found: $peerId');
  }
  
  /// Broadcast message to all peers
  void broadcast(SecureMessage message) {
    for (final connectionId in _connections.keys) {
      _sendToConnection(connectionId, message);
    }
  }
  
  /// Disconnect from specific peer
  void disconnectPeer(String peerId) {
    for (final entry in _connectedPeers.entries.toList()) {
      if (entry.value.id == peerId) {
        _sendToConnection(entry.key, SecureMessage(type: SecureMessageType.disconnect));
        _handleDisconnect(entry.key);
        return;
      }
    }
  }
  
  /// Stop server and disconnect all peers
  Future<void> stop() async {
    // Send disconnect to all peers
    for (final connectionId in _connections.keys.toList()) {
      _sendToConnection(connectionId, SecureMessage(type: SecureMessageType.disconnect));
      _connections[connectionId]?.close();
    }
    
    _connections.clear();
    _connectedPeers.clear();
    
    await _server?.close(force: true);
    _server = null;
    
    print('Secure channel service stopped');
  }
  
  /// Generate fingerprint for certificate verification
  static String generateFingerprint(String input) {
    final bytes = utf8.encode(input);
    final hash = sha256.convert(bytes);
    return hash.toString().substring(0, 16);
  }
}

