import 'package:flutter/foundation.dart';
import 'package:scn/services/http_server_service.dart';
import 'package:scn/services/discovery_service.dart';
import 'package:scn/providers/receive_provider.dart';
import 'package:scn/providers/chat_provider.dart';
import 'package:scn/providers/device_provider.dart';

/// Main application service that coordinates all services
class AppService extends ChangeNotifier {
  final HttpServerService _httpServer = HttpServerService();
  final DiscoveryService _discovery = DiscoveryService();
  
  bool _initialized = false;
  bool _running = false;
  String _deviceAlias = 'SCN Device';
  
  bool get initialized => _initialized;
  bool get running => _running;
  int get port => _httpServer.port;
  String get deviceAlias => _deviceAlias;
  
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
  
  void setDeviceAlias(String alias) {
    _deviceAlias = alias;
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

