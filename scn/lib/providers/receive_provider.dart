import 'package:flutter/foundation.dart';
import 'package:scn/models/session.dart';
import 'package:scn/models/device.dart';

/// Provider for managing receive sessions
class ReceiveProvider extends ChangeNotifier {
  ReceiveSession? _currentSession;
  final List<ReceiveSession> _history = [];
  
  ReceiveSession? get currentSession => _currentSession;
  List<ReceiveSession> get history => List.unmodifiable(_history);
  
  void startSession(ReceiveSession session) {
    debugPrint('📥 ReceiveProvider.startSession: ${session.files.length} files from ${session.sender.alias}');
    _currentSession = session;
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
    notifyListeners();
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
}

