import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scn/models/remote_peer.dart';

/// Provider for managing remote peers state
class RemotePeerProvider extends ChangeNotifier {
  final List<RemotePeer> _peers = [];
  final List<PeerInvitation> _pendingInvitations = [];
  NetworkSettings _settings = const NetworkSettings();
  
  static const String _peersKey = 'remote_peers';
  static const String _settingsKey = 'network_settings';
  
  List<RemotePeer> get peers => List.unmodifiable(_peers);
  List<RemotePeer> get localPeers => _peers.where((p) => p.type == PeerType.local).toList();
  List<RemotePeer> get remotePeers => _peers.where((p) => p.type == PeerType.remote).toList();
  List<RemotePeer> get connectedPeers => _peers.where((p) => p.status == PeerStatus.connected).toList();
  List<RemotePeer> get favoritePeers => _peers.where((p) => p.isFavorite).toList();
  List<PeerInvitation> get pendingInvitations => List.unmodifiable(_pendingInvitations);
  NetworkSettings get settings => _settings;
  
  /// Load saved peers and settings from SharedPreferences
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load peers
      final peersJson = prefs.getString(_peersKey);
      if (peersJson != null) {
        final peersList = jsonDecode(peersJson) as List<dynamic>;
        _peers.clear();
        for (final peerData in peersList) {
          final peer = RemotePeer.fromJson(peerData as Map<String, dynamic>);
          // Reset status to disconnected on load
          _peers.add(peer.copyWith(status: PeerStatus.disconnected));
        }
      }
      
      // Load settings
      final settingsJson = prefs.getString(_settingsKey);
      if (settingsJson != null) {
        _settings = NetworkSettings.fromJson(
          jsonDecode(settingsJson) as Map<String, dynamic>,
        );
      }
      
      notifyListeners();
      debugPrint('Loaded ${_peers.length} peers');
    } catch (e) {
      debugPrint('Error loading peers: $e');
    }
  }
  
  /// Save peers to SharedPreferences
  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Only save remote and favorite peers
      final peersToSave = _peers
          .where((p) => p.type == PeerType.remote || p.isFavorite)
          .map((p) => p.toJson())
          .toList();
      
      await prefs.setString(_peersKey, jsonEncode(peersToSave));
    } catch (e) {
      debugPrint('Error saving peers: $e');
    }
  }
  
  /// Save settings to SharedPreferences
  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_settingsKey, jsonEncode(_settings.toJson()));
    } catch (e) {
      debugPrint('Error saving settings: $e');
    }
  }
  
  /// Add or update a peer
  void addPeer(RemotePeer peer) {
    final index = _peers.indexWhere((p) => p.id == peer.id);
    if (index >= 0) {
      // Update existing peer, preserve favorite status
      _peers[index] = peer.copyWith(
        isFavorite: _peers[index].isFavorite,
        type: _peers[index].type,
      );
    } else {
      _peers.add(peer);
    }
    notifyListeners();
    _save();
  }
  
  /// Update peer status
  void updatePeerStatus(String peerId, PeerStatus status, {String? errorMessage}) {
    final index = _peers.indexWhere((p) => p.id == peerId);
    if (index >= 0) {
      _peers[index] = _peers[index].copyWith(
        status: status,
        errorMessage: errorMessage,
        lastSeen: status == PeerStatus.connected ? DateTime.now() : _peers[index].lastSeen,
      );
      notifyListeners();
    }
  }
  
  /// Toggle favorite status
  void toggleFavorite(String peerId) {
    final index = _peers.indexWhere((p) => p.id == peerId);
    if (index >= 0) {
      _peers[index] = _peers[index].copyWith(
        isFavorite: !_peers[index].isFavorite,
      );
      notifyListeners();
      _save();
    }
  }
  
  /// Remove a peer
  void removePeer(String peerId) {
    _peers.removeWhere((p) => p.id == peerId);
    notifyListeners();
    _save();
  }
  
  /// Clear all peers
  void clearPeers({bool keepFavorites = true}) {
    if (keepFavorites) {
      _peers.removeWhere((p) => !p.isFavorite);
    } else {
      _peers.clear();
    }
    notifyListeners();
    _save();
  }
  
  /// Add discovered peers from mesh network
  void addDiscoveredPeers(List<RemotePeer> peers) {
    for (final peer in peers) {
      if (!_peers.any((p) => p.id == peer.id)) {
        _peers.add(peer.copyWith(
          type: PeerType.remote,
          status: PeerStatus.disconnected,
        ));
      }
    }
    notifyListeners();
    _save();
  }
  
  /// Add pending invitation
  void addInvitation(PeerInvitation invitation) {
    // Check if already exists
    if (!_pendingInvitations.any((i) => i.id == invitation.id)) {
      _pendingInvitations.add(invitation);
      notifyListeners();
    }
  }
  
  /// Remove invitation
  void removeInvitation(String invitationId) {
    _pendingInvitations.removeWhere((i) => i.id == invitationId);
    notifyListeners();
  }
  
  /// Clear all invitations
  void clearInvitations() {
    _pendingInvitations.clear();
    notifyListeners();
  }
  
  /// Update network settings
  Future<void> updateSettings(NetworkSettings settings) async {
    _settings = settings;
    notifyListeners();
    await _saveSettings();
  }
  
  /// Update specific setting
  Future<void> setMeshEnabled(bool enabled) async {
    _settings = _settings.copyWith(meshEnabled: enabled);
    notifyListeners();
    await _saveSettings();
  }
  
  Future<void> setSharePeers(bool enabled) async {
    _settings = _settings.copyWith(sharePeers: enabled);
    notifyListeners();
    await _saveSettings();
  }
  
  Future<void> setAcceptWithoutPassword(bool enabled) async {
    _settings = _settings.copyWith(acceptWithoutPassword: enabled);
    notifyListeners();
    await _saveSettings();
  }
  
  Future<void> setConnectionPassword(String? password) async {
    _settings = _settings.copyWith(
      connectionPassword: password,
      acceptWithoutPassword: password == null || password.isEmpty,
    );
    notifyListeners();
    await _saveSettings();
  }
}

