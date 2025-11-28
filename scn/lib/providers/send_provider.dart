import 'package:flutter/foundation.dart';
import 'package:scn/models/session.dart';
import 'package:scn/models/file_info.dart';

/// Provider for managing send sessions
class SendProvider extends ChangeNotifier {
  SendSession? _currentSession;
  final List<SendSession> _history = [];
  final List<FileInfo> _selectedFiles = [];
  final Map<String, String> _filePaths = {}; // fileId -> localPath
  
  SendSession? get currentSession => _currentSession;
  List<SendSession> get history => List.unmodifiable(_history);
  List<FileInfo> get selectedFiles => List.unmodifiable(_selectedFiles);
  
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
}

