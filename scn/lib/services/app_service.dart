import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scn/services/http_server_service.dart';
import 'package:scn/services/discovery_service.dart';
import 'package:scn/services/mesh_network_service.dart';
import 'package:scn/providers/receive_provider.dart';
import 'package:scn/providers/chat_provider.dart';
import 'package:scn/providers/device_provider.dart';
import 'package:scn/providers/remote_peer_provider.dart';
import 'package:scn/utils/device_name_generator.dart';
import 'package:scn/models/device_visibility.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

/// Main application service that coordinates all services
class AppService extends ChangeNotifier {
  final HttpServerService _httpServer = HttpServerService();
  final DiscoveryService _discovery = DiscoveryService();
  final MeshNetworkService _meshNetwork = MeshNetworkService();
  
  bool _initialized = false;
  bool _running = false;
  String _deviceAlias = 'SCN Device';
  String _deviceFingerprint = '';
  DeviceVisibility _deviceVisibility = DeviceVisibility.enabled;
  static const String _deviceAliasKey = 'device_alias';
  static const String _deviceVisibilityKey = 'device_visibility';
  static const String _deviceFingerprintKey = 'device_fingerprint';
  
  RemotePeerProvider? _peerProvider;
  
  bool get initialized => _initialized;
  bool get running => _running;
  int get port => _httpServer.port;
  String get deviceAlias => _deviceAlias;
  String get deviceFingerprint => _deviceFingerprint;
  DeviceVisibility get deviceVisibility => _deviceVisibility;
  MeshNetworkService? get meshService => _running ? _meshNetwork : null;
  
  void setProviders({
    ReceiveProvider? receiveProvider,
    ChatProvider? chatProvider,
    DeviceProvider? deviceProvider,
    RemotePeerProvider? peerProvider,
  }) {
    _httpServer.setProviders(
      receiveProvider: receiveProvider,
      chatProvider: chatProvider,
    );
    _discovery.setProvider(deviceProvider ?? DeviceProvider());
    
    if (peerProvider != null) {
      _peerProvider = peerProvider;
      _meshNetwork.setProvider(peerProvider);
    }
    
    _updateDeviceInfo();
  }
  
  void _updateDeviceInfo() {
    _discovery.setDeviceInfo(
      alias: _deviceAlias,
      port: port,
      fingerprint: _deviceFingerprint,
      serverRunning: _running,
    );
    _httpServer.setDeviceInfo(alias: _deviceAlias);
    _meshNetwork.setDeviceInfo(
      deviceId: _deviceFingerprint,
      alias: _deviceAlias,
      fingerprint: _deviceFingerprint,
    );
  }
  
  /// Load device alias and fingerprint from SharedPreferences
  Future<void> loadDeviceAlias() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load alias
      final savedAlias = prefs.getString(_deviceAliasKey);
      if (savedAlias != null && savedAlias.isNotEmpty) {
        _deviceAlias = savedAlias;
      } else {
        _deviceAlias = DeviceNameGenerator.generateUnique();
        await prefs.setString(_deviceAliasKey, _deviceAlias);
        debugPrint('Generated new device name: $_deviceAlias');
      }
      
      // Load or generate fingerprint
      final savedFingerprint = prefs.getString(_deviceFingerprintKey);
      if (savedFingerprint != null && savedFingerprint.isNotEmpty) {
        _deviceFingerprint = savedFingerprint;
      } else {
        _deviceFingerprint = _generateFingerprint();
        await prefs.setString(_deviceFingerprintKey, _deviceFingerprint);
        debugPrint('Generated new device fingerprint: $_deviceFingerprint');
      }
      
      // Load visibility
      final savedVisibility = prefs.getInt(_deviceVisibilityKey);
      if (savedVisibility != null && savedVisibility < DeviceVisibility.values.length) {
        _deviceVisibility = DeviceVisibility.values[savedVisibility];
      }
      
      _updateDeviceInfo();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading device settings: $e');
      _deviceAlias = DeviceNameGenerator.generateUnique();
      _deviceFingerprint = _generateFingerprint();
      _updateDeviceInfo();
      notifyListeners();
    }
  }
  
  String _generateFingerprint() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final random = timestamp.hashCode ^ _deviceAlias.hashCode;
    final bytes = utf8.encode('$random-$_deviceAlias-$timestamp');
    final hash = sha256.convert(bytes);
    return hash.toString().substring(0, 16);
  }
  
  /// Set device alias and save to SharedPreferences
  Future<void> setDeviceAlias(String alias) async {
    if (alias.trim().isEmpty) {
      return;
    }
    
    _deviceAlias = alias.trim();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_deviceAliasKey, _deviceAlias);
    } catch (e) {
      debugPrint('Error saving device alias: $e');
    }
    
    _updateDeviceInfo();
    notifyListeners();
  }
  
  /// Set device visibility and save to SharedPreferences
  Future<void> setDeviceVisibility(DeviceVisibility visibility) async {
    _deviceVisibility = visibility;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_deviceVisibilityKey, visibility.index);
    } catch (e) {
      debugPrint('Error saving device visibility: $e');
    }
    
    _updateDeviceInfo();
    notifyListeners();
  }
  
  Future<void> initialize() async {
    if (_running) return;
    
    try {
      // Stop services first if they were running before
      if (_initialized) {
        try {
          await _httpServer.stop();
          await _discovery.stop();
          await _meshNetwork.stop();
        } catch (e) {
          debugPrint('Error stopping services: $e');
        }
      }
      
      // Load remote peers if provider is set
      await _peerProvider?.load();
      
      // Start HTTP server
      await _httpServer.start();
      
      // Start device discovery
      await _discovery.start();
      
      // Start mesh network service
      try {
        if (_peerProvider != null) {
          _meshNetwork.updateSettings(_peerProvider!.settings);
        }
        await _meshNetwork.start();
      } catch (e) {
        debugPrint('Mesh network failed to start (non-fatal): $e');
      }
      
      _initialized = true;
      _running = true;
      _updateDeviceInfo();
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to initialize app: $e');
      _running = false;
      _updateDeviceInfo();
      notifyListeners();
      rethrow;
    }
  }
  
  Future<void> stop() async {
    if (!_running) return;
    
    try {
      await _httpServer.stop();
      await _discovery.stop();
      await _meshNetwork.stop();
      
      _running = false;
      _updateDeviceInfo();
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to stop app: $e');
      _running = false;
      _updateDeviceInfo();
      notifyListeners();
    }
  }
  
  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
