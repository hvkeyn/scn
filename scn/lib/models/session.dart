import 'package:scn/models/device.dart';
import 'package:scn/models/file_info.dart';

/// Session status
enum SessionStatus {
  waiting,
  sending,
  receiving,
  finished,
  finishedWithErrors,
  cancelled,
}

/// File transfer status
enum FileStatus {
  queue,
  sending,
  receiving,
  finished,
  failed,
  skipped,
}

/// Receiving file state
class ReceivingFile {
  final FileInfo file;
  final FileStatus status;
  final String? token;
  final String? desiredName;
  final String? savedPath;
  final String? errorMessage;
  
  ReceivingFile({
    required this.file,
    required this.status,
    this.token,
    this.desiredName,
    this.savedPath,
    this.errorMessage,
  });
  
  ReceivingFile copyWith({
    FileInfo? file,
    FileStatus? status,
    String? token,
    String? desiredName,
    String? savedPath,
    String? errorMessage,
  }) => ReceivingFile(
    file: file ?? this.file,
    status: status ?? this.status,
    token: token ?? this.token,
    desiredName: desiredName ?? this.desiredName,
    savedPath: savedPath ?? this.savedPath,
    errorMessage: errorMessage ?? this.errorMessage,
  );
}

/// Sending file state
class SendingFile {
  final FileInfo file;
  final FileStatus status;
  final String? token;
  final String? localPath;
  final List<int>? bytes;
  final String? errorMessage;
  
  SendingFile({
    required this.file,
    required this.status,
    this.token,
    this.localPath,
    this.bytes,
    this.errorMessage,
  });
  
  SendingFile copyWith({
    FileInfo? file,
    FileStatus? status,
    String? token,
    String? localPath,
    String? Function()? localPathFn,
    List<int>? bytes,
    String? errorMessage,
  }) => SendingFile(
    file: file ?? this.file,
    status: status ?? this.status,
    token: token ?? this.token,
    localPath: localPath ?? (localPathFn != null ? localPathFn() : this.localPath),
    bytes: bytes ?? this.bytes,
    errorMessage: errorMessage ?? this.errorMessage,
  );
}

/// Receive session state
class ReceiveSession {
  final String sessionId;
  final Device sender;
  final Map<String, ReceivingFile> files;
  final SessionStatus status;
  final DateTime? startTime;
  final DateTime? endTime;
  final String destinationDirectory;
  
  ReceiveSession({
    required this.sessionId,
    required this.sender,
    required this.files,
    required this.status,
    this.startTime,
    this.endTime,
    required this.destinationDirectory,
  });
}

/// Send session state
class SendSession {
  final String sessionId;
  final Device target;
  final Map<String, SendingFile> files;
  final SessionStatus status;
  final DateTime? startTime;
  final DateTime? endTime;
  
  SendSession({
    required this.sessionId,
    required this.target,
    required this.files,
    required this.status,
    this.startTime,
    this.endTime,
  });
}

