import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Service for file operations
class FileService {
  static Future<String> getDefaultDownloadDirectory() async {
    if (Platform.isWindows) {
      return '${Platform.environment['USERPROFILE']}\\Downloads';
    } else if (Platform.isLinux) {
      return '${Platform.environment['HOME']}/Downloads';
    } else if (Platform.isMacOS) {
      return '${Platform.environment['HOME']}/Downloads';
    }
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }
  
  static Future<String> ensureDirectory(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return path;
  }
  
  static Future<String> saveFile({
    required String destinationDirectory,
    required String fileName,
    required Stream<List<int>> stream,
  }) async {
    await ensureDirectory(destinationDirectory);
    
    final filePath = '${destinationDirectory.replaceAll('\\', '/')}/$fileName';
    final file = File(filePath);
    
    // Handle file name conflicts
    String finalPath = filePath;
    int counter = 1;
    while (await File(finalPath).exists()) {
      final ext = fileName.split('.').last;
      final nameWithoutExt = fileName.substring(0, fileName.lastIndexOf('.'));
      finalPath = '${destinationDirectory.replaceAll('\\', '/')}/${nameWithoutExt}_$counter.$ext';
      counter++;
    }
    
    final sink = await File(finalPath).openWrite();
    await for (final chunk in stream) {
      sink.add(chunk);
    }
    await sink.close();
    
    return finalPath;
  }
  
  static Future<List<int>> readFileBytes(String filePath) async {
    final file = File(filePath);
    return await file.readAsBytes();
  }
  
  static Future<int> getFileSize(String filePath) async {
    final file = File(filePath);
    return await file.length();
  }
}

