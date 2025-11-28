import 'dart:io';

/// Utility for opening files and folders
class FileOpener {
  /// Open file with default application
  static Future<bool> openFile(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', [path]);
        return true;
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [path]);
        return true;
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
        return true;
      }
      return false;
    } catch (e) {
      print('Failed to open file: $e');
      return false;
    }
  }
  
  /// Open folder containing the file
  static Future<bool> openFolder(String filePath) async {
    try {
      final file = File(filePath);
      final directory = file.parent.path;
      
      if (Platform.isWindows) {
        // Open folder and select the file
        await Process.run('explorer', ['/select,', filePath]);
        return true;
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [directory]);
        return true;
      } else if (Platform.isMacOS) {
        await Process.run('open', ['-R', filePath]);
        return true;
      }
      return false;
    } catch (e) {
      print('Failed to open folder: $e');
      return false;
    }
  }
  
  /// Open directory
  static Future<bool> openDirectory(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', [path]);
        return true;
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [path]);
        return true;
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
        return true;
      }
      return false;
    } catch (e) {
      print('Failed to open directory: $e');
      return false;
    }
  }
}

