import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:scn/models/remote_peer.dart';
import 'package:scn/services/secure_channel_service.dart';
import 'package:scn/providers/remote_peer_provider.dart';

/// Mesh Network Service
/// Manages peer-to-peer connections and mesh network synchronization
class MeshNetworkService {
  final SecureChannelService _secureChannel = SecureChannelService();
  RemotePeerProvider? _peerProvider;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  
  String _deviceId = '';
  String _deviceAlias = 'SCN Device';
  bool _isRunning = false;
  
  // Callbacks
  Function(RemotePeer peer)? onPeerConnected;
  Function(String peerId)? onPeerDisconnected;
  Function(PeerInvitation invitation)? onInvitation;
  
  bool get isRunning => _isRunning;
  List<RemotePeer> get connectedPeers => _secureChannel.connectedPeers;
  
  void setProvider(RemotePeerProvider provider) {
    _peerProvider = provider;
    _secureChannel.setSettings(provider.settings);
  }
  
  void setDeviceInfo({String? deviceId, String? alias, String? fingerprint}) {
    if (deviceId != null) _deviceId = deviceId;
    if (alias != null) _deviceAlias = alias;
    
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
      // Setup callbacks
      _secureChannel.onMessage = _handleMessage;
      _secureChannel.onPeerConnected = _handlePeerConnected;
      _secureChannel.onPeerDisconnected = _handlePeerDisconnected;
      _secureChannel.onInvitation = _handleInvitation;
      
      // Start secure channel server
      await _secureChannel.start();
      
      _isRunning = true;
      
      // Start periodic tasks
      _startPeriodicTasks();
      
      // Try to reconnect to saved remote peers
      _reconnectSavedPeers();
      
      debugPrint('Mesh network service started');
    } catch (e) {
      debugPrint('Failed to start mesh network: $e');
      _isRunning = false;
      rethrow;
    }
  }
  
  void _startPeriodicTasks() {
    // Reconnect timer - check every 30 seconds
    _reconnectTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _reconnectDisconnectedPeers();
    });
    
    // Ping timer - keep connections alive
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _sendPingToAll();
    });
  }
  
  void _reconnectSavedPeers() {
    final provider = _peerProvider;
    if (provider == null) return;
    
    // Get saved remote peers that are disconnected
    final remotePeers = provider.remotePeers
        .where((p) => p.status == PeerStatus.disconnected)
        .toList();
    
    for (final peer in remotePeers) {
      _connectToPeer(peer);
    }
  }
  
  void _reconnectDisconnectedPeers() {
    final provider = _peerProvider;
    if (provider == null) return;
    
    // Reconnect to favorite peers that are disconnected
    final disconnectedFavorites = provider.favoritePeers
        .where((p) => p.status == PeerStatus.disconnected && p.type == PeerType.remote)
        .toList();
    
    for (final peer in disconnectedFavorites) {
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
        // Handle other messages
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
      
      // Don't add ourselves
      if (peer.id != _deviceId) {
        provider.addPeer(peer);
        
        // Optionally auto-connect to discovered peer
        if (peer.status == PeerStatus.disconnected) {
          // Don't auto-connect, just add to list
          debugPrint('Discovered peer via mesh: ${peer.alias}');
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
        (s) => s.name == status,
        orElse: () => PeerStatus.disconnected,
      );
      _peerProvider?.updatePeerStatus(peerId, peerStatus);
    }
  }
  
  void _handlePeerConnected(RemotePeer peer) {
    _peerProvider?.addPeer(peer);
    _peerProvider?.updatePeerStatus(peer.id, PeerStatus.connected);
    onPeerConnected?.call(peer);
    
    debugPrint('Peer connected: ${peer.alias}');
  }
  
  void _handlePeerDisconnected(String peerId) {
    _peerProvider?.updatePeerStatus(peerId, PeerStatus.disconnected);
    onPeerDisconnected?.call(peerId);
    
    debugPrint('Peer disconnected: $peerId');
  }
  
  void _handleInvitation(PeerInvitation invitation) {
    _peerProvider?.addInvitation(invitation);
    onInvitation?.call(invitation);
    
    debugPrint('Received invitation from: ${invitation.fromAlias}');
  }
  
  /// Connect to a remote peer by address
  Future<bool> connectToAddress({
    required String address,
    int port = 53318,
    String? password,
  }) async {
    try {
      return await _secureChannel.connectToPeer(
        address: address,
        port: port,
        password: password,
      );
    } catch (e) {
      debugPrint('Failed to connect to $address:$port: $e');
      return false;
    }
  }
  
  /// Disconnect from a specific peer
  void disconnectPeer(String peerId) {
    _secureChannel.disconnectPeer(peerId);
    _peerProvider?.updatePeerStatus(peerId, PeerStatus.disconnected);
  }
  
  /// Accept an invitation
  Future<bool> acceptInvitation(PeerInvitation invitation, {String? password}) async {
    _peerProvider?.removeInvitation(invitation.id);
    return await _secureChannel.acceptInvitation(invitation, password: password);
  }
  
  /// Reject an invitation
  void rejectInvitation(PeerInvitation invitation) {
    _secureChannel.rejectInvitation(invitation);
    _peerProvider?.removeInvitation(invitation.id);
  }
  
  /// Send data to a specific peer
  void sendToPeer(String peerId, Map<String, dynamic> data) {
    _secureChannel.sendToPeer(peerId, SecureMessage(
      type: SecureMessageType.data,
      senderId: _deviceId,
      senderAlias: _deviceAlias,
      payload: data,
    ));
  }
  
  /// Broadcast data to all connected peers
  void broadcast(Map<String, dynamic> data) {
    _secureChannel.broadcast(SecureMessage(
      type: SecureMessageType.data,
      senderId: _deviceId,
      senderAlias: _deviceAlias,
      payload: data,
    ));
  }
  
  /// Update settings
  void updateSettings(NetworkSettings settings) {
    _secureChannel.setSettings(settings);
  }
  
  /// Stop mesh network service
  Future<void> stop() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    
    _pingTimer?.cancel();
    _pingTimer = null;
    
    await _secureChannel.stop();
    _isRunning = false;
    
    debugPrint('Mesh network service stopped');
  }
}

