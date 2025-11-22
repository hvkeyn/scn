import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:scn/providers/send_provider.dart';
import 'package:scn/providers/device_provider.dart';
import 'package:scn/services/http_client_service.dart';
import 'package:scn/services/file_service.dart';
import 'package:scn/models/device.dart';
import 'package:scn/models/file_info.dart';
import 'package:scn/models/session.dart';
import 'package:uuid/uuid.dart';

class SendTab extends StatelessWidget {
  const SendTab({super.key});

  @override
  Widget build(BuildContext context) {
    final sendProvider = context.watch<SendProvider>();
    final deviceProvider = context.watch<DeviceProvider>();
    
    return Scaffold(
      body: sendProvider.currentSession != null
          ? _buildSessionView(context, sendProvider.currentSession!)
          : _buildMainView(context, sendProvider, deviceProvider),
    );
  }

  Widget _buildMainView(
    BuildContext context,
    SendProvider sendProvider,
    DeviceProvider deviceProvider,
  ) {
    return Column(
      children: [
        if (sendProvider.selectedFiles.isNotEmpty) _buildSelectedFiles(context, sendProvider),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.send, size: 64),
              const SizedBox(height: 16),
              Text(
                'Send Files',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => _pickFiles(context, sendProvider),
                icon: const Icon(Icons.add),
                label: const Text('Select Files'),
              ),
              const SizedBox(height: 16),
              if (deviceProvider.devices.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'No devices found. Make sure devices are on the same network.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                )
              else ...[
                const SizedBox(height: 32),
                Text(
                  'Available Devices',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: deviceProvider.devices.length,
                    itemBuilder: (context, index) {
                      final device = deviceProvider.devices[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(_getDeviceIcon(device.type)),
                          title: Text(device.alias),
                          subtitle: Text('${device.ip}:${device.port}'),
                          trailing: sendProvider.selectedFiles.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.send),
                                  onPressed: () => _sendFiles(context, sendProvider, device),
                                ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedFiles(BuildContext context, SendProvider sendProvider) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Text(
                  'Selected Files (${sendProvider.selectedFiles.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => sendProvider.clearFiles(),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: sendProvider.selectedFiles.length,
              itemBuilder: (context, index) {
                final file = sendProvider.selectedFiles[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_getFileIcon(file.fileType)),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: 80,
                            child: Text(
                              file.fileName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () => sendProvider.removeFile(file.id),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionView(BuildContext context, SendSession session) {
    return Column(
      children: [
        AppBar(
          title: Text('Sending to ${session.target.alias}'),
          actions: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                context.read<SendProvider>().cancelSession();
              },
            ),
          ],
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: session.files.length,
            itemBuilder: (context, index) {
              final fileEntry = session.files.entries.elementAt(index);
              final file = fileEntry.value;
              
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(_getFileIcon(file.file.fileType)),
                  title: Text(file.file.fileName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${_formatFileSize(file.file.size)}'),
                      if (file.status == FileStatus.sending)
                        const LinearProgressIndicator(),
                      if (file.status == FileStatus.finished)
                        const Text('Sent', style: TextStyle(color: Colors.green)),
                      if (file.status == FileStatus.failed)
                        Text('Error: ${file.errorMessage}', style: const TextStyle(color: Colors.red)),
                    ],
                  ),
                  trailing: _getStatusIcon(file.status),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _pickFiles(BuildContext context, SendProvider sendProvider) async {
    final result = await file_picker.FilePicker.platform.pickFiles(allowMultiple: true);
    
    if (result != null && result.files.isNotEmpty) {
      for (final platformFile in result.files) {
        String? localPath;
        List<int>? bytes;
        
        if (platformFile.path != null) {
          localPath = platformFile.path;
        } else if (platformFile.bytes != null) {
          bytes = platformFile.bytes;
        }
        
        final fileInfo = FileInfo(
          id: const Uuid().v4(),
          fileName: platformFile.name,
          size: platformFile.size ?? 0,
          fileType: _getFileTypeFromName(platformFile.name),
          mimeType: platformFile.extension,
        );
        
        sendProvider.addFile(fileInfo, localPath: platformFile.path);
        
        // Store local path in sending file if we have a session
        if (sendProvider.currentSession != null && localPath != null) {
          final session = sendProvider.currentSession!;
          final sendingFile = session.files[fileInfo.id];
          if (sendingFile != null) {
            sendProvider.startSession(SendSession(
              sessionId: session.sessionId,
              target: session.target,
              files: {
                ...session.files,
                fileInfo.id: sendingFile.copyWith(localPath: localPath),
              },
              status: session.status,
              startTime: session.startTime,
              endTime: session.endTime,
            ));
          }
        }
      }
    }
  }

  Future<void> _sendFiles(
    BuildContext context,
    SendProvider sendProvider,
    Device device,
  ) async {
    if (sendProvider.selectedFiles.isEmpty) return;
    
    final httpClient = HttpClientService();
    final sessionId = const Uuid().v4();
    
      // Create sending files map
      final sendingFiles = <String, SendingFile>{};
      for (final fileInfo in sendProvider.selectedFiles) {
        sendingFiles[fileInfo.id] = SendingFile(
          file: fileInfo,
          status: FileStatus.queue,
          localPath: sendProvider.getFilePath(fileInfo.id),
        );
      }
    
    // Create session
    final session = SendSession(
      sessionId: sessionId,
      target: device,
      files: sendingFiles,
      status: SessionStatus.waiting,
    );
    
    sendProvider.startSession(session);
    
    try {
      // Prepare upload
      final remoteSessionId = await httpClient.prepareUpload(
        device: device,
        files: sendingFiles.map((key, value) => MapEntry(key, value.file)),
        alias: 'SCN Device',
        version: '1.0.0',
      );
      
      if (remoteSessionId == null) {
        sendProvider.cancelSession();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to prepare upload')),
          );
        }
        return;
      }
      
      // Get file tokens (accept files)
      final tokens = await httpClient.getFileTokens(
        device: device,
        sessionId: remoteSessionId,
        files: sendingFiles.map((key, value) => MapEntry(key, value.file)),
      );
      
      if (tokens == null || tokens.isEmpty) {
        sendProvider.finishSession();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No files accepted')),
          );
        }
        return;
      }
      
      // Update session with tokens
      final updatedFiles = <String, SendingFile>{};
      for (final entry in sendingFiles.entries) {
        final token = tokens[entry.key];
        updatedFiles[entry.key] = entry.value.copyWith(
          token: token,
          status: token != null ? FileStatus.queue : FileStatus.skipped,
        );
      }
      
      sendProvider.startSession(SendSession(
        sessionId: sessionId,
        target: device,
        files: updatedFiles,
        status: SessionStatus.sending,
        startTime: DateTime.now(),
      ));
      
      // Send files
      for (final entry in updatedFiles.entries) {
        final file = entry.value;
        if (file.token == null || file.localPath == null) continue;
        
        sendProvider.updateFileStatus(entry.key, FileStatus.sending);
        
        final success = await httpClient.uploadFile(
          device: device,
          sessionId: remoteSessionId,
          fileId: entry.key,
          token: file.token!,
          filePath: file.localPath!,
          fileSize: file.file.size,
          onProgress: (progress) {
            // Progress tracking can be added here
          },
        );
        
        if (success) {
          sendProvider.updateFileStatus(entry.key, FileStatus.finished);
        } else {
          sendProvider.updateFileStatus(
            entry.key,
            FileStatus.failed,
            errorMessage: 'Upload failed',
          );
        }
      }
      
      sendProvider.finishSession();
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Files sent to ${device.alias}')),
        );
      }
    } catch (e) {
      sendProvider.cancelSession();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  IconData _getDeviceIcon(DeviceType type) {
    switch (type) {
      case DeviceType.mobile:
        return Icons.smartphone;
      case DeviceType.desktop:
        return Icons.computer;
      case DeviceType.web:
        return Icons.language;
      default:
        return Icons.devices;
    }
  }

  IconData _getFileIcon(FileType type) {
    switch (type) {
      case FileType.image:
        return Icons.image;
      case FileType.video:
        return Icons.video_file;
      case FileType.audio:
        return Icons.audio_file;
      case FileType.text:
        return Icons.text_snippet;
      default:
        return Icons.insert_drive_file;
    }
  }

  FileType _getFileTypeFromName(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) return FileType.image;
    if (['mp4', 'avi', 'mov', 'mkv'].contains(ext)) return FileType.video;
    if (['mp3', 'wav', 'ogg'].contains(ext)) return FileType.audio;
    if (['txt', 'md', 'json'].contains(ext)) return FileType.text;
    return FileType.other;
  }

  Widget _getStatusIcon(FileStatus status) {
    switch (status) {
      case FileStatus.finished:
        return const Icon(Icons.check_circle, color: Colors.green);
      case FileStatus.failed:
        return const Icon(Icons.error, color: Colors.red);
      case FileStatus.sending:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      default:
        return const Icon(Icons.pending);
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
