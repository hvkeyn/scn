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
    _currentSession = session;
    notifyListeners();
  }
  
  void updateFileStatus(String fileId, FileStatus status, {String? errorMessage}) {
    if (_currentSession == null) return;
    
    final file = _currentSession!.files[fileId];
    if (file == null) return;
    
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
    if (_currentSession == null) return;
    
    _history.insert(0, _currentSession!);
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

