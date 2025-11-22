import 'dart:io';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:scn/services/file_service.dart';
import 'package:scn/models/device.dart';
import 'package:scn/models/file_info.dart';
import 'package:scn/models/session.dart';
import 'package:scn/models/chat_message.dart';
import 'package:scn/providers/receive_provider.dart';
import 'package:scn/providers/chat_provider.dart';
import 'package:uuid/uuid.dart';

/// HTTP server service for receiving files
class HttpServerService {
  HttpServer? _server;
  final Router _router = Router();
  final Uuid _uuid = const Uuid();
  
  int _port = 53317;
  int get port => _port;
  
  ReceiveProvider? _receiveProvider;
  ChatProvider? _chatProvider;
  String _deviceAlias = 'SCN Device';
  String _deviceVersion = '1.0.0';
  
  HttpServerService() {
    _setupRoutes();
  }
  
  void setProviders({
    ReceiveProvider? receiveProvider,
    ChatProvider? chatProvider,
  }) {
    _receiveProvider = receiveProvider;
    _chatProvider = chatProvider;
  }
  
  void setDeviceInfo({String? alias, String? version}) {
    if (alias != null) _deviceAlias = alias;
    if (version != null) _deviceVersion = version;
  }
  
  void _setupRoutes() {
    // Device info endpoint
    _router.get('/api/info', (Request request) {
      return Response.ok(
        jsonEncode({
          'alias': _deviceAlias,
          'version': _deviceVersion,
          'deviceModel': Platform.operatingSystem,
          'deviceType': 'desktop',
          'fingerprint': 'scn-device-${_uuid.v4()}',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    });
    
    // Register endpoint (for responding to announcements)
    _router.post('/api/register', (Request request) async {
      return await _handleRegister(request);
    });
    
    // Prepare upload (receive files request)
    _router.post('/api/session', (Request request) async {
      return await _handlePrepareUpload(request);
    });
    
    // Accept files
    _router.post('/api/accept', (Request request) async {
      return await _handleAcceptFiles(request);
    });
    
    // Upload file
    _router.post('/api/upload', (Request request) async {
      return await _handleFileUpload(request);
    });
    
    // Chat endpoint
    _router.post('/api/chat', (Request request) async {
      return await _handleChatMessage(request);
    });
  }
  
  Future<Response> _handleRegister(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      
      // Extract device info from register request
      final device = Device(
        id: data['fingerprint'] as String? ?? _uuid.v4(),
        alias: data['alias'] as String? ?? 'Unknown',
        ip: request.headers['x-forwarded-for'] ?? 
            request.headers['remote-addr'] ?? 
            'unknown',
        port: int.tryParse(data['port']?.toString() ?? '53317') ?? 53317,
        type: DeviceType.desktop,
      );
      
      // Notify device provider (if available)
      // This will be handled by the discovery service
      
      return Response.ok(
        jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('Error in register: $e');
      return Response(500, body: jsonEncode({'error': e.toString()}));
    }
  }
  
  Future<Response> _handlePrepareUpload(Request request) async {
    try {
      if (_receiveProvider?.currentSession != null) {
        return Response(409, body: jsonEncode({'error': 'Another session is active'}));
      }
      
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      
      final info = data['info'] as Map<String, dynamic>;
      final filesData = data['files'] as Map<String, dynamic>;
      
      if (filesData.isEmpty) {
        return Response(400, body: jsonEncode({'error': 'No files provided'}));
      }
      
      final sender = Device(
        id: info['fingerprint'] as String? ?? _uuid.v4(),
        alias: info['alias'] as String? ?? 'Unknown',
        ip: request.headers['x-forwarded-for'] ?? 
            request.headers['remote-addr'] ?? 
            'unknown',
        port: int.tryParse(info['port']?.toString() ?? '53317') ?? 53317,
        type: DeviceType.desktop,
      );
      
      final files = <String, ReceivingFile>{};
      for (final entry in filesData.entries) {
        final fileData = entry.value as Map<String, dynamic>;
        final fileInfo = FileInfo(
          id: entry.key,
          fileName: fileData['fileName'] as String,
          size: fileData['size'] as int? ?? 0,
          mimeType: fileData['mimeType'] as String?,
          fileType: _parseFileType(fileData['fileType'] as String?),
        );
        
        files[entry.key] = ReceivingFile(
          file: fileInfo,
          status: FileStatus.queue,
        );
      }
      
      final sessionId = _uuid.v4();
      final destinationDir = await FileService.getDefaultDownloadDirectory();
      
      final session = ReceiveSession(
        sessionId: sessionId,
        sender: sender,
        files: files,
        status: SessionStatus.waiting,
        destinationDirectory: destinationDir,
      );
      
      _receiveProvider?.startSession(session);
      
      return Response.ok(
        jsonEncode({
          'sessionId': sessionId,
          'accepted': false, // User needs to accept
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('Error in prepare upload: $e');
      return Response(500, body: jsonEncode({'error': e.toString()}));
    }
  }
  
  Future<Response> _handleAcceptFiles(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final sessionId = data['sessionId'] as String?;
      final selectedFiles = data['files'] as List<dynamic>?;
      
      if (sessionId == null || _receiveProvider?.currentSession?.sessionId != sessionId) {
        return Response(404, body: jsonEncode({'error': 'Session not found'}));
      }
      
      final session = _receiveProvider!.currentSession!;
      final tokens = <String, String>{};
      
      for (final fileId in selectedFiles ?? []) {
        final fileIdStr = fileId.toString();
        if (session.files.containsKey(fileIdStr)) {
          tokens[fileIdStr] = _uuid.v4();
        }
      }
      
      // Update session status
      _receiveProvider!.startSession(ReceiveSession(
        sessionId: session.sessionId,
        sender: session.sender,
        files: session.files,
        status: SessionStatus.receiving,
        startTime: DateTime.now(),
        destinationDirectory: session.destinationDirectory,
      ));
      
      return Response.ok(
        jsonEncode({'files': tokens}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('Error in accept files: $e');
      return Response(500, body: jsonEncode({'error': e.toString()}));
    }
  }
  
  Future<Response> _handleFileUpload(Request request) async {
    try {
      final sessionId = request.url.queryParameters['sessionId'];
      final fileId = request.url.queryParameters['fileId'];
      final token = request.url.queryParameters['token'];
      
      if (sessionId == null || fileId == null || token == null) {
        return Response(400, body: jsonEncode({'error': 'Missing parameters'}));
      }
      
      final session = _receiveProvider?.currentSession;
      if (session == null || session.sessionId != sessionId) {
        return Response(404, body: jsonEncode({'error': 'Session not found'}));
      }
      
      final receivingFile = session.files[fileId];
      if (receivingFile == null) {
        return Response(404, body: jsonEncode({'error': 'File not found'}));
      }
      
      // Update file status to receiving
      _receiveProvider?.updateFileStatus(fileId, FileStatus.receiving);
      
      // Save file
      final fileName = receivingFile.desiredName ?? receivingFile.file.fileName;
      final filePath = await FileService.saveFile(
        destinationDirectory: session.destinationDirectory,
        fileName: fileName,
        stream: request.read(),
      );
      
      // Update file with saved path
      final updatedFiles = Map<String, ReceivingFile>.from(session.files);
      updatedFiles[fileId] = receivingFile.copyWith(
        status: FileStatus.finished,
        savedPath: filePath,
      );
      
      _receiveProvider?.startSession(ReceiveSession(
        sessionId: session.sessionId,
        sender: session.sender,
        files: updatedFiles,
        status: session.status,
        startTime: session.startTime,
        endTime: session.endTime,
        destinationDirectory: session.destinationDirectory,
      ));
      
      // Check if all files are finished
      final allFinished = session.files.values.every(
        (f) => f.status == FileStatus.finished || f.status == FileStatus.failed,
      );
      
      if (allFinished) {
        _receiveProvider?.finishSession();
      }
      
      return Response.ok(jsonEncode({'status': 'ok'}));
    } catch (e) {
      print('Error in file upload: $e');
      _receiveProvider?.updateFileStatus(
        request.url.queryParameters['fileId'] ?? '',
        FileStatus.failed,
        errorMessage: e.toString(),
      );
      return Response(500, body: jsonEncode({'error': e.toString()}));
    }
  }
  
  Future<Response> _handleChatMessage(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final message = data['message'] as String?;
      
      if (message == null || message.isEmpty) {
        return Response(400, body: jsonEncode({'error': 'Message is required'}));
      }
      
      // Get sender info from headers or request
      final senderId = request.headers['x-device-id'] ?? _uuid.v4();
      final senderAlias = request.headers['x-device-alias'] ?? 'Unknown';
      
      // Add message to chat provider
      _chatProvider?.addMessage(
        ChatMessage(
          id: _uuid.v4(),
          deviceId: senderId,
          deviceAlias: senderAlias,
          message: message,
          timestamp: DateTime.now(),
          isFromMe: false,
        ),
      );
      
      return Response.ok(jsonEncode({'status': 'ok'}));
    } catch (e) {
      print('Error in chat message: $e');
      return Response(500, body: jsonEncode({'error': e.toString()}));
    }
  }
  
  FileType _parseFileType(String? type) {
    if (type == null) return FileType.other;
    switch (type.toLowerCase()) {
      case 'image':
        return FileType.image;
      case 'video':
        return FileType.video;
      case 'audio':
        return FileType.audio;
      case 'text':
        return FileType.text;
      default:
        return FileType.other;
    }
  }
  
  Future<void> start({int? port}) async {
    if (_server != null) {
      throw StateError('Server already running');
    }
    
    if (port != null) {
      _port = port;
    }
    
    // Try multiple ports if the default one is busy
    final portsToTry = [_port, _port + 1, _port + 2, _port + 3, _port + 4];
    Exception? lastException;
    
    for (final tryPort in portsToTry) {
      try {
        _server = await shelf_io.serve(
          _router,
          InternetAddress.anyIPv4,
          tryPort,
        );
        
        _port = tryPort;
        print('HTTP Server started on port $_port');
        return;
      } on SocketException catch (e) {
        // Port is busy, try next one
        lastException = e;
        print('Port $tryPort is busy, trying next port...');
        continue;
      } catch (e) {
        // Other error, rethrow
        print('Failed to start HTTP server: $e');
        rethrow;
      }
    }
    
    // All ports failed
    throw lastException ?? StateError('Failed to start server on any port');
  }
  
  Future<void> stop() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      print('HTTP Server stopped');
    }
  }
}
