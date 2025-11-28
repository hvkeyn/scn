import 'dart:io';

/// Simple file logger for debugging
class AppLogger {
  static File? _logFile;
  static bool _initialized = false;
  static String _deviceId = '';
  static String _shortId = '';
  
  /// Initialize logger - clears old log
  static Future<void> init() async {
    if (_initialized) return;
    
    try {
      // Get executable directory
      final exePath = Platform.resolvedExecutable;
      final exeDir = File(exePath).parent.path;
      
      // Use unique ID based on start time
      final startTime = DateTime.now().millisecondsSinceEpoch;
      _logFile = File('$exeDir/scn_debug_$startTime.log');
      
      // Clear old log files (keep only this one)
      try {
        final dir = Directory(exeDir);
        await for (final entity in dir.list()) {
          if (entity is File && entity.path.contains('scn_debug_') && entity.path.endsWith('.log')) {
            try { await entity.delete(); } catch (_) {}
          }
        }
      } catch (_) {}
      
      await _logFile!.create();
      
      _initialized = true;
      log('=== SCN Log Started ${DateTime.now()} ===');
      log('Log file: ${_logFile!.path}');
    } catch (e) {
      print('Failed to init logger: $e');
    }
  }
  
  /// Set device ID for logging
  static void setDeviceId(String deviceId) {
    _deviceId = deviceId;
    _shortId = deviceId.length > 6 ? deviceId.substring(0, 6) : deviceId;
    log('Device ID set: $deviceId ($_shortId)');
  }
  
  /// Log message to file
  static void log(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final prefix = _shortId.isNotEmpty ? '[$timestamp|$_shortId]' : '[$timestamp]';
    final line = '$prefix $message';
    
    // Also print to console (for debug builds)
    print(line);
    
    // Write to file
    try {
      _logFile?.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (e) {
      // Ignore file write errors
    }
  }
  
  /// Get log file path
  static String? get logPath => _logFile?.path;
}

