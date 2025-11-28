import 'dart:io';
import 'package:flutter/foundation.dart';

/// Configuration for test mode - allows running multiple instances
class TestConfig {
  static TestConfig? _instance;
  
  /// Current instance number (0 = normal mode, 1+ = test instances)
  final int instanceNumber;
  
  /// Whether test mode is enabled
  bool get isTestMode => instanceNumber > 0;
  
  /// Base port for HTTP server
  static const int basePort = 53317;
  
  /// Base port for secure mesh
  static const int baseMeshPort = 53318;
  
  /// Maximum test instances
  static const int maxInstances = 5;
  
  /// Get the HTTP port for this instance
  int get httpPort => basePort + (instanceNumber * 10);
  
  /// Get the mesh port for this instance  
  int get meshPort => baseMeshPort + (instanceNumber * 10);
  
  /// Get display name suffix for this instance
  String get instanceSuffix => isTestMode ? ' [Test #$instanceNumber]' : '';
  
  /// Get SharedPreferences key prefix for this instance
  String get storagePrefix => isTestMode ? 'test${instanceNumber}_' : '';
  
  /// Get window title suffix
  String get windowTitle => isTestMode ? 'SCN [Test Instance #$instanceNumber]' : 'SCN';
  
  TestConfig._({required this.instanceNumber});
  
  /// Initialize test config from command line arguments
  static void init(List<String> args) {
    int instance = 0;
    
    for (final arg in args) {
      if (arg.startsWith('--instance=')) {
        instance = int.tryParse(arg.substring('--instance='.length)) ?? 0;
        break;
      }
      if (arg == '--test') {
        instance = 1; // Default test instance
        break;
      }
    }
    
    _instance = TestConfig._(instanceNumber: instance);
    
    if (_instance!.isTestMode) {
      debugPrint('╔══════════════════════════════════════════╗');
      debugPrint('║     TEST INSTANCE #$instance                     ║');
      debugPrint('║     HTTP: ${_instance!.httpPort}  Mesh: ${_instance!.meshPort}              ║');
      debugPrint('║     Storage: ${_instance!.storagePrefix}*                  ║');
      debugPrint('╚══════════════════════════════════════════╝');
    }
  }
  
  /// Get the current test config
  static TestConfig get current {
    _instance ??= TestConfig._(instanceNumber: 0);
    return _instance!;
  }
  
  /// Get all possible test instance ports (for local discovery)
  static List<int> get allTestPorts {
    return List.generate(maxInstances, (i) => basePort + (i * 10));
  }
  
  /// Get all possible mesh ports
  static List<int> get allMeshPorts {
    return List.generate(maxInstances, (i) => baseMeshPort + (i * 10));
  }
  
  /// Launch a new test instance
  static Future<bool> launchTestInstance(int instanceNumber) async {
    if (instanceNumber < 1 || instanceNumber >= maxInstances) {
      debugPrint('Invalid instance number: $instanceNumber');
      return false;
    }
    
    try {
      final executablePath = Platform.resolvedExecutable;
      debugPrint('Launching test instance #$instanceNumber from: $executablePath');
      
      await Process.start(
        executablePath,
        ['--instance=$instanceNumber'],
        mode: ProcessStartMode.detached,
      );
      
      debugPrint('Test instance #$instanceNumber launched successfully');
      return true;
    } catch (e) {
      debugPrint('Failed to launch test instance: $e');
      return false;
    }
  }
  
  /// Find next available instance number
  static Future<int> findNextAvailableInstance() async {
    // Simple approach: just return the next number
    // In real implementation, could check which ports are in use
    for (int i = 1; i < maxInstances; i++) {
      final port = basePort + (i * 10);
      if (!await _isPortInUse(port)) {
        return i;
      }
    }
    return 1; // Default to 1 if all seem busy
  }
  
  static Future<bool> _isPortInUse(int port) async {
    try {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      await socket.close();
      return false; // Port is free
    } catch (e) {
      return true; // Port is in use
    }
  }
  
  /// Exit this test instance
  static void exitTestInstance() {
    if (current.isTestMode) {
      debugPrint('Exiting test instance #${current.instanceNumber}');
      exit(0);
    }
  }
}

