import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scn/services/http_server_service.dart';
import 'package:scn/services/discovery_service.dart';
import 'package:scn/providers/receive_provider.dart';
import 'package:scn/providers/chat_provider.dart';
import 'package:scn/providers/device_provider.dart';
import 'package:scn/utils/device_name_generator.dart';
import 'package:scn/models/device_visibility.dart';

/// Main application service that coordinates all services
class AppService extends ChangeNotifier {
  final HttpServerService _httpServer = HttpServerService();
  final DiscoveryService _discovery = DiscoveryService();
  
  bool _initialized = false;
  bool _running = false;
  String _deviceAlias = 'SCN Device';
  DeviceVisibility _deviceVisibility = DeviceVisibility.enabled;
  static const String _deviceAliasKey = 'device_alias';
  static const String _deviceVisibilityKey = 'device_visibility';
  
  bool get initialized => _initialized;
  bool get running => _running;
  int get port => _httpServer.port;
  String get deviceAlias => _deviceAlias;
  DeviceVisibility get deviceVisibility => _deviceVisibility;
  
  void setProviders({
    ReceiveProvider? receiveProvider,
    ChatProvider? chatProvider,
    DeviceProvider? deviceProvider,
  }) {
    _httpServer.setProviders(
      receiveProvider: receiveProvider,
      chatProvider: chatProvider,
    );
    _discovery.setProvider(deviceProvider ?? DeviceProvider());
    _updateDeviceInfo();
  }
  
  void _updateDeviceInfo() {
    _discovery.setDeviceInfo(
      alias: _deviceAlias,
      port: port,
      serverRunning: _running,
    );
    _httpServer.setDeviceInfo(alias: _deviceAlias);
  }
  
  /// Load device alias from SharedPreferences or generate a new one
  Future<void> loadDeviceAlias() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedAlias = prefs.getString(_deviceAliasKey);
      
      if (savedAlias != null && savedAlias.isNotEmpty) {
        _deviceAlias = savedAlias;
      } else {
        // Generate a new random name if none exists
        _deviceAlias = DeviceNameGenerator.generateUnique();
        await prefs.setString(_deviceAliasKey, _deviceAlias);
        debugPrint('Generated new device name: $_deviceAlias');
      }
      
      _updateDeviceInfo();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading device alias: $e');
      // Fallback to generated name
      _deviceAlias = DeviceNameGenerator.generateUnique();
      _updateDeviceInfo();
      notifyListeners();
    }
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
    // If already running, do nothing
    if (_running) return;
    
    try {
      // Stop services first if they were running before
      if (_initialized) {
        try {
          await _httpServer.stop();
          await _discovery.stop();
        } catch (e) {
          debugPrint('Error stopping services: $e');
        }
      }
      
      // Start HTTP server
      await _httpServer.start();
      
      // Start device discovery
      await _discovery.start();
      
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
      
      _running = false;
      // Keep _initialized = true so we can restart
      _updateDeviceInfo();
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to stop app: $e');
      // Still mark as stopped even if error
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

