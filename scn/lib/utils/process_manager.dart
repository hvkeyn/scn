import 'dart:io';
import 'package:flutter/foundation.dart';

/// Utility class for managing process instances
class ProcessManager {

  /// Kills all other instances of scn.exe except the current one
  /// Uses process start time to identify the newest process (current one)
  /// Returns the number of processes killed
  static Future<int> killOtherInstances() async {
    if (!Platform.isWindows) {
      // On non-Windows platforms, this is not implemented
      return 0;
    }

    try {
      // Wait a bit to ensure current process is fully started
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Get list of all scn.exe processes with start time
      final result = await Process.run(
        'wmic',
        ['process', 'where', 'name="scn.exe"', 'get', 'ProcessId,CreationDate', '/format:csv'],
      );

      if (result.exitCode != 0) {
        return 0;
      }

      final output = result.stdout as String;
      if (output.trim().isEmpty) {
        return 0;
      }

      final lines = output.split('\n');
      final processes = <Map<String, String>>[];

      // Parse CSV output (skip header)
      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        final parts = line.split(',');
        if (parts.length >= 3) {
          try {
            final pid = parts[1].trim();
            final creationDate = parts[2].trim();
            if (pid.isNotEmpty && creationDate.isNotEmpty) {
              processes.add({
                'pid': pid,
                'creationDate': creationDate,
              });
            }
          } catch (e) {
            continue;
          }
        }
      }

      if (processes.length <= 1) {
        return 0; // Only one or no processes
      }

      // Sort by creation date (newest first)
      processes.sort((a, b) => b['creationDate']!.compareTo(a['creationDate']!));
      
      // Kill all except the newest (current) process
      int killedCount = 0;
      for (int i = 1; i < processes.length; i++) {
        try {
          final pid = processes[i]['pid']!;
          final killResult = await Process.run(
            'taskkill',
            ['/PID', pid, '/F'],
          );

          if (killResult.exitCode == 0) {
            killedCount++;
            debugPrint('Killed scn.exe process with PID: $pid');
          }
        } catch (e) {
          continue;
        }
      }

      // Wait a bit for processes to terminate
      if (killedCount > 0) {
        await Future.delayed(const Duration(milliseconds: 300));
      }

      return killedCount;
    } catch (e) {
      debugPrint('Error killing other instances: $e');
      return 0;
    }
  }

  /// Parse a CSV line, handling quoted values
  static List<String> _parseCsvLine(String line) {
    final List<String> result = [];
    String current = '';
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        result.add(current);
        current = '';
      } else {
        current += char;
      }
    }

    if (current.isNotEmpty) {
      result.add(current);
    }

    return result;
  }

}

