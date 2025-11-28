import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scn/models/session.dart';
import 'package:scn/models/file_info.dart';
import 'package:scn/models/device.dart';

/// Provider for managing send sessions
class SendProvider extends ChangeNotifier {
  SendSession? _currentSession;
  final List<SendSession> _history = [];
  final List<FileInfo> _selectedFiles = [];
  final Map<String, String> _filePaths = {}; // fileId -> localPath
  String _myDeviceId = '';
  bool _historyLoaded = false;
  
  String get _storageKey => 'send_history_$_myDeviceId';
  
  SendSession? get currentSession => _currentSession;
  List<SendSession> get history => List.unmodifiable(_history);
  List<FileInfo> get selectedFiles => List.unmodifiable(_selectedFiles);
  
  SendProvider();
  
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
    debugPrint('📂 Loading send history with key: $_storageKey');
    
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
        debugPrint('📤 Loaded ${_history.length} send sessions');
      }
    } catch (e) {
      debugPrint('Failed to load send history: $e');
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
      debugPrint('Failed to save send history: $e');
    }
  }
  
  Map<String, dynamic> _sessionToJson(SendSession session) => {
    'sessionId': session.sessionId,
    'target': {
      'id': session.target.id,
      'alias': session.target.alias,
      'ip': session.target.ip,
      'port': session.target.port,
      'type': session.target.type.name,
    },
    'status': session.status.name,
    'startTime': session.startTime?.toIso8601String(),
    'endTime': session.endTime?.toIso8601String(),
    'files': session.files.map((k, v) => MapEntry(k, {
      'fileId': v.file.id,
      'fileName': v.file.fileName,
      'fileSize': v.file.size,
      'fileType': v.file.fileType.name,
      'status': v.status.name,
      'localPath': v.localPath,
      'errorMessage': v.errorMessage,
    })),
  };
  
  SendSession _sessionFromJson(Map<String, dynamic> json) {
    final targetJson = json['target'] as Map<String, dynamic>;
    final filesJson = json['files'] as Map<String, dynamic>;
    
    return SendSession(
      sessionId: json['sessionId'] as String,
      target: Device(
        id: targetJson['id'] as String,
        alias: targetJson['alias'] as String,
        ip: targetJson['ip'] as String,
        port: targetJson['port'] as int,
        type: DeviceType.values.firstWhere(
          (e) => e.name == targetJson['type'],
          orElse: () => DeviceType.desktop,
        ),
      ),
      status: SessionStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => SessionStatus.finished,
      ),
      startTime: json['startTime'] != null ? DateTime.parse(json['startTime'] as String) : null,
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime'] as String) : null,
      files: filesJson.map((k, v) {
        final f = v as Map<String, dynamic>;
        return MapEntry(k, SendingFile(
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
          localPath: f['localPath'] as String?,
          errorMessage: f['errorMessage'] as String?,
        ));
      }),
    );
  }
  
  void addFile(FileInfo file, {String? localPath}) {
    if (!_selectedFiles.any((f) => f.id == file.id)) {
      _selectedFiles.add(file);
      if (localPath != null) {
        _filePaths[file.id] = localPath;
      }
      notifyListeners();
    }
  }
  
  String? getFilePath(String fileId) => _filePaths[fileId];
  
  void removeFile(String fileId) {
    _selectedFiles.removeWhere((f) => f.id == fileId);
    notifyListeners();
  }
  
  void clearFiles() {
    _selectedFiles.clear();
    notifyListeners();
  }
  
  void startSession(SendSession session) {
    _currentSession = session;
    notifyListeners();
  }
  
  void updateFileStatus(String fileId, FileStatus status, {String? errorMessage}) {
    if (_currentSession == null) return;
    
    final file = _currentSession!.files[fileId];
    if (file == null) return;
    
    final updatedFiles = Map<String, SendingFile>.from(_currentSession!.files);
    updatedFiles[fileId] = file.copyWith(
      status: status,
      errorMessage: errorMessage,
      progress: status == FileStatus.finished ? 1.0 : file.progress,
    );
    
    _currentSession = SendSession(
      sessionId: _currentSession!.sessionId,
      target: _currentSession!.target,
      files: updatedFiles,
      status: _currentSession!.status,
      startTime: _currentSession!.startTime,
      endTime: _currentSession!.endTime,
    );
    
    notifyListeners();
  }
  
  void updateFileProgress(String fileId, double progress, int bytesSent) {
    if (_currentSession == null) return;
    
    final file = _currentSession!.files[fileId];
    if (file == null) return;
    
    final updatedFiles = Map<String, SendingFile>.from(_currentSession!.files);
    updatedFiles[fileId] = file.copyWith(
      progress: progress,
      bytesSent: bytesSent,
    );
    
    _currentSession = SendSession(
      sessionId: _currentSession!.sessionId,
      target: _currentSession!.target,
      files: updatedFiles,
      status: _currentSession!.status,
      startTime: _currentSession!.startTime,
      endTime: _currentSession!.endTime,
    );
    
    notifyListeners();
  }
  
  /// Get overall transfer progress (0.0 to 1.0)
  double get overallProgress {
    if (_currentSession == null) return 0.0;
    
    int totalSize = 0;
    int totalSent = 0;
    
    for (final file in _currentSession!.files.values) {
      totalSize += file.file.size;
      totalSent += file.bytesSent;
    }
    
    return totalSize > 0 ? totalSent / totalSize : 0.0;
  }
  
  /// Get count of files by status
  int countFilesByStatus(FileStatus status) {
    if (_currentSession == null) return 0;
    return _currentSession!.files.values.where((f) => f.status == status).length;
  }
  
  void finishSession() {
    if (_currentSession == null) return;
    
    _history.insert(0, _currentSession!);
    _currentSession = null;
    _saveHistory();
    notifyListeners();
  }
  
  void cancelSession() {
    if (_currentSession == null) return;
    
    _currentSession = SendSession(
      sessionId: _currentSession!.sessionId,
      target: _currentSession!.target,
      files: _currentSession!.files,
      status: SessionStatus.cancelled,
      startTime: _currentSession!.startTime,
      endTime: DateTime.now(),
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
