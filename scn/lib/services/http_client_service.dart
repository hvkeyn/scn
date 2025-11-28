import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:scn/models/device.dart';
import 'package:scn/models/file_info.dart';
import 'package:scn/models/session.dart';

/// HTTP client service for sending files
class HttpClientService {
  Future<Map<String, dynamic>?> getDeviceInfo(Device device) async {
    try {
      final response = await http.get(
        Uri.parse('${device.url}/api/info'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 3));
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      print('getDeviceInfo: status ${response.statusCode}');
      return null;
    } catch (e) {
      print('Failed to get device info from ${device.url}: $e');
      return null;
    }
  }
  
  Future<String?> prepareUpload({
    required Device device,
    required Map<String, FileInfo> files,
    required String alias,
    required String version,
  }) async {
    try {
      final requestBody = {
        'info': {
          'alias': alias,
          'version': version,
          'deviceModel': Platform.operatingSystem,
          'deviceType': 'desktop',
        },
        'files': {
          for (final file in files.values)
            file.id: {
              'id': file.id,
              'fileName': file.fileName,
              'size': file.size,
              'mimeType': file.mimeType,
              'fileType': file.fileType.name,
            },
        },
      };
      
      final response = await http.post(
        Uri.parse('${device.url}/api/session'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body) as Map<String, dynamic>;
        return responseData['sessionId'] as String?;
      }
      return null;
    } catch (e) {
      print('Failed to prepare upload: $e');
      return null;
    }
  }
  
  Future<Map<String, String>?> getFileTokens({
    required Device device,
    required String sessionId,
    required Map<String, FileInfo> files,
  }) async {
    try {
      final requestBody = {
        'sessionId': sessionId,
        'files': files.keys.toList(),
      };
      
      final response = await http.post(
        Uri.parse('${device.url}/api/accept'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body) as Map<String, dynamic>;
        final filesMap = responseData['files'] as Map<String, dynamic>?;
        if (filesMap != null) {
          return filesMap.map((key, value) => MapEntry(key, value.toString()));
        }
      }
      return null;
    } catch (e) {
      print('Failed to get file tokens: $e');
      return null;
    }
  }
  
  Future<bool> uploadFile({
    required Device device,
    required String sessionId,
    required String fileId,
    required String token,
    required String filePath,
    required int fileSize,
    Function(double)? onProgress,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        print('File not found: $filePath');
        return false;
      }
      
      final uri = Uri.parse('${device.url}/api/upload')
          .replace(queryParameters: {
        'sessionId': sessionId,
        'fileId': fileId,
        'token': token,
      });
      
      // Use stream request for better progress tracking
      final request = http.StreamedRequest('POST', uri);
      request.headers['Content-Type'] = 'application/octet-stream';
      request.contentLength = fileSize;
      
      // Stream file data
      final fileStream = file.openRead();
      int uploadedBytes = 0;
      
      fileStream.listen(
        (chunk) {
          request.sink.add(chunk);
          uploadedBytes += chunk.length;
          if (onProgress != null && fileSize > 0) {
            onProgress(uploadedBytes / fileSize);
          }
        },
        onDone: () {
          request.sink.close();
        },
        onError: (error) {
          request.sink.close();
        },
      );
      
      final streamedResponse = await request.send().timeout(
        const Duration(minutes: 10),
        onTimeout: () {
          throw TimeoutException('Upload timeout');
        },
      );
      
      final response = await http.Response.fromStream(streamedResponse);
      return response.statusCode == 200;
    } catch (e) {
      print('Failed to upload file: $e');
      return false;
    }
  }
  
  String _myDeviceId = '';
  String _myAlias = '';
  
  void setMyInfo({required String deviceId, required String alias}) {
    _myDeviceId = deviceId;
    _myAlias = alias;
  }
  
  Future<bool> sendMessage({
    required Device device,
    required String message,
    bool isGroupMessage = false,
  }) async {
    try {
      final requestBody = {
        'message': message,
        'type': 'text',
        'isGroupMessage': isGroupMessage,
        'senderId': _myDeviceId,
        'senderAlias': _myAlias,
      };
      
      final response = await http.post(
        Uri.parse('${device.url}/api/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 10));
      
      return response.statusCode == 200;
    } catch (e) {
      print('Failed to send message: $e');
      return false;
    }
  }
  
  Future<bool> post(String url, {Map<String, String>? headers, String? body}) async {
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: headers ?? {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 5));
      
      return response.statusCode == 200;
    } catch (e) {
      print('POST failed: $e');
      return false;
    }
  }
  
  /// Send file through chat (direct upload with chat metadata)
  Future<bool> sendFileWithChat({
    required Device target,
    required String filePath,
    required FileInfo fileInfo,
    required String senderId,
    required String senderAlias,
    bool isGroupMessage = false,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        print('File not found: $filePath');
        return false;
      }
      
      final uri = Uri.parse('${target.url}/api/chat-file')
          .replace(queryParameters: {
        'fileId': fileInfo.id,
        'fileName': fileInfo.fileName,
        'fileSize': fileInfo.size.toString(),
        'senderId': senderId,
        'senderAlias': senderAlias,
        'isGroupMessage': isGroupMessage.toString(),
      });
      
      // Upload file
      final request = http.StreamedRequest('POST', uri);
      request.headers['Content-Type'] = 'application/octet-stream';
      request.contentLength = fileInfo.size;
      
      final fileStream = file.openRead();
      fileStream.listen(
        (chunk) => request.sink.add(chunk),
        onDone: () => request.sink.close(),
        onError: (error) => request.sink.close(),
      );
      
      final streamedResponse = await request.send().timeout(
        const Duration(minutes: 10),
      );
      
      return streamedResponse.statusCode == 200;
    } catch (e) {
      print('Failed to send chat file: $e');
      return false;
    }
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
}

