import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scn/models/session.dart';
import 'package:scn/models/device.dart';
import 'package:scn/models/file_info.dart';

/// Provider for managing receive sessions
class ReceiveProvider extends ChangeNotifier {
  ReceiveSession? _currentSession;
  final List<ReceiveSession> _history = [];
  int _unviewedCount = 0;  // Counter for badge
  String _myDeviceId = '';
  bool _historyLoaded = false;
  
  String get _storageKey => 'receive_history_$_myDeviceId';
  
  ReceiveSession? get currentSession => _currentSession;
  List<ReceiveSession> get history => List.unmodifiable(_history);
  int get unviewedCount => _unviewedCount;
  
  ReceiveProvider();
  
  void setMyDeviceId(String deviceId) {
    if (_myDeviceId == deviceId) return;
    _myDeviceId = deviceId;
    if (!_historyLoaded) {
      _loadHistory();
    }
  }
  
  // Load history from storage
  Future<void> _loadHistory() async {
    if (_myDeviceId.isEmpty) return;
    
    _historyLoaded = true;
    debugPrint('📂 Loading receive history with key: $_storageKey');
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_storageKey);
      if (json != null) {
        final data = jsonDecode(json) as Map<String, dynamic>;
        final sessions = data['sessions'] as List<dynamic>?;
        if (sessions != null) {
          _history.clear();
          for (final s in sessions) {
            _history.add(_sessionFromJson(s as Map<String, dynamic>));
          }
        }
        debugPrint('📥 Loaded ${_history.length} receive sessions');
      }
    } catch (e) {
      debugPrint('Failed to load receive history: $e');
    }
    notifyListeners();
  }
  
  // Save history to storage
  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessions = _history.map((s) => _sessionToJson(s)).toList();
      final json = jsonEncode({'sessions': sessions});
      await prefs.setString(_storageKey, json);
    } catch (e) {
      debugPrint('Failed to save receive history: $e');
    }
  }
  
  Map<String, dynamic> _sessionToJson(ReceiveSession session) => {
    'sessionId': session.sessionId,
    'sender': {
      'id': session.sender.id,
      'alias': session.sender.alias,
      'ip': session.sender.ip,
      'port': session.sender.port,
      'type': session.sender.type.name,
    },
    'status': session.status.name,
    'startTime': session.startTime?.toIso8601String(),
    'endTime': session.endTime?.toIso8601String(),
    'destinationDirectory': session.destinationDirectory,
    'files': session.files.map((k, v) => MapEntry(k, {
      'fileId': v.file.id,
      'fileName': v.file.fileName,
      'fileSize': v.file.size,
      'fileType': v.file.fileType.name,
      'status': v.status.name,
      'savedPath': v.savedPath,
      'errorMessage': v.errorMessage,
    })),
  };
  
  ReceiveSession _sessionFromJson(Map<String, dynamic> json) {
    final senderJson = json['sender'] as Map<String, dynamic>;
    final filesJson = json['files'] as Map<String, dynamic>;
    
    return ReceiveSession(
      sessionId: json['sessionId'] as String,
      sender: Device(
        id: senderJson['id'] as String,
        alias: senderJson['alias'] as String,
        ip: senderJson['ip'] as String,
        port: senderJson['port'] as int,
        type: DeviceType.values.firstWhere(
          (e) => e.name == senderJson['type'],
          orElse: () => DeviceType.desktop,
        ),
      ),
      status: SessionStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => SessionStatus.finished,
      ),
      startTime: json['startTime'] != null ? DateTime.parse(json['startTime'] as String) : null,
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime'] as String) : null,
      destinationDirectory: json['destinationDirectory'] as String? ?? '',
      files: filesJson.map((k, v) {
        final f = v as Map<String, dynamic>;
        return MapEntry(k, ReceivingFile(
          file: FileInfo(
            id: f['fileId'] as String,
            fileName: f['fileName'] as String,
            size: f['fileSize'] as int,
            fileType: FileType.values.firstWhere(
              (e) => e.name == f['fileType'],
              orElse: () => FileType.other,
            ),
          ),
          status: FileStatus.values.firstWhere(
            (e) => e.name == f['status'],
            orElse: () => FileStatus.finished,
          ),
          savedPath: f['savedPath'] as String?,
          errorMessage: f['errorMessage'] as String?,
        ));
      }),
    );
  }
  
  void startSession(ReceiveSession session) {
    debugPrint('📥 ReceiveProvider.startSession: ${session.files.length} files from ${session.sender.alias}');
    
    // Only increment badge for NEW sessions (not updates to existing)
    final isNewSession = _currentSession == null || 
                         _currentSession!.sessionId != session.sessionId;
    
    _currentSession = session;
    
    if (isNewSession) {
      _unviewedCount++;  // Increment badge only for new sessions
      debugPrint('   New session - badge count: $_unviewedCount');
    }
    
    notifyListeners();
  }
  
  void updateFileStatus(String fileId, FileStatus status, {String? errorMessage}) {
    if (_currentSession == null) return;
    
    final file = _currentSession!.files[fileId];
    if (file == null) return;
    
    debugPrint('📥 ReceiveProvider.updateFileStatus: $fileId -> $status');
    
    final updatedFiles = Map<String, ReceivingFile>.from(_currentSession!.files);
    updatedFiles[fileId] = file.copyWith(
      status: status,
      errorMessage: errorMessage,
    );
    
    _currentSession = ReceiveSession(
      sessionId: _currentSession!.sessionId,
      sender: _currentSession!.sender,
      files: updatedFiles,
      status: _currentSession!.status,
      startTime: _currentSession!.startTime,
      endTime: _currentSession!.endTime,
      destinationDirectory: _currentSession!.destinationDirectory,
    );
    
    notifyListeners();
  }
  
  void finishSession() {
    if (_currentSession == null) {
      debugPrint('📥 ReceiveProvider.finishSession: No current session!');
      return;
    }
    
    debugPrint('📥 ReceiveProvider.finishSession: Saving to history');
    debugPrint('   Files: ${_currentSession!.files.length}');
    for (final f in _currentSession!.files.values) {
      debugPrint('   - ${f.file.fileName}: ${f.status} -> ${f.savedPath}');
    }
    
    _history.insert(0, _currentSession!);
    debugPrint('   History now has ${_history.length} sessions');
    
    _currentSession = null;
    _saveHistory();
    notifyListeners();
  }
  
  /// Mark all as viewed (reset badge)
  void markAsViewed() {
    if (_unviewedCount > 0) {
      _unviewedCount = 0;
      notifyListeners();
    }
  }
  
  void cancelSession() {
    if (_currentSession == null) return;
    
    _currentSession = ReceiveSession(
      sessionId: _currentSession!.sessionId,
      sender: _currentSession!.sender,
      files: _currentSession!.files,
      status: SessionStatus.cancelled,
      startTime: _currentSession!.startTime,
      endTime: DateTime.now(),
      destinationDirectory: _currentSession!.destinationDirectory,
    );
    
    finishSession();
  }
  
  /// Delete specific session from history
  void deleteSession(String sessionId) {
    _history.removeWhere((s) => s.sessionId == sessionId);
    _saveHistory();
    notifyListeners();
  }
  
  /// Clear all history
  Future<void> clearHistory() async {
    _history.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    notifyListeners();
  }
}
