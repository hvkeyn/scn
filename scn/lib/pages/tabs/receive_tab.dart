import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scn/providers/receive_provider.dart';
import 'package:scn/providers/device_provider.dart';
import 'package:scn/services/app_service.dart';
import 'package:scn/services/http_client_service.dart';
import 'package:scn/models/session.dart';
import 'package:scn/models/file_info.dart';

class ReceiveTab extends StatefulWidget {
  const ReceiveTab({super.key});

  @override
  State<ReceiveTab> createState() => _ReceiveTabState();
}

class _ReceiveTabState extends State<ReceiveTab> {
  final Set<String> _selectedFiles = {};

  @override
  Widget build(BuildContext context) {
    final receiveProvider = context.watch<ReceiveProvider>();
    final appService = context.watch<AppService>();
    
    return Scaffold(
      body: receiveProvider.currentSession != null
          ? _buildSessionView(context, receiveProvider.currentSession!)
          : _buildWaitingView(context, appService),
    );
  }

  Widget _buildWaitingView(BuildContext context, AppService appService) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              appService.running ? Icons.wifi : Icons.wifi_off,
              size: 80,
              color: appService.running ? Colors.green : Colors.grey,
            ),
            const SizedBox(height: 24),
            Text(
              appService.running ? 'Waiting for files...' : 'Server is offline',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              appService.running 
                ? 'Ready to receive files from nearby devices'
                : 'Start the server to receive files',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (appService.running) ...[
              const SizedBox(height: 32),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text(
                        'Server Status',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Port: ${appService.port}',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSessionView(BuildContext context, ReceiveSession session) {
    final receiveProvider = context.watch<ReceiveProvider>();
    final isWaiting = session.status == SessionStatus.waiting;
    
    return Column(
      children: [
        AppBar(
          title: Text('Receiving from ${session.sender.alias}'),
          actions: [
            if (isWaiting)
              TextButton(
                onPressed: () {
                  _acceptFiles(context, receiveProvider, session);
                },
                child: const Text('Accept'),
              ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                receiveProvider.cancelSession();
                _selectedFiles.clear();
              },
            ),
          ],
        ),
        if (isWaiting)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Select files to receive',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: session.files.length,
            itemBuilder: (context, index) {
              final fileEntry = session.files.entries.elementAt(index);
              final fileId = fileEntry.key;
              final file = fileEntry.value;
              final isSelected = _selectedFiles.contains(fileId);
              
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: isWaiting
                      ? Checkbox(
                          value: isSelected,
                          onChanged: (value) {
                            setState(() {
                              if (value == true) {
                                _selectedFiles.add(fileId);
                              } else {
                                _selectedFiles.remove(fileId);
                              }
                            });
                          },
                        )
                      : _getFileIcon(file.file.fileType),
                  title: Text(file.desiredName ?? file.file.fileName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${_formatFileSize(file.file.size)}'),
                      if (file.status == FileStatus.sending || file.status == FileStatus.receiving)
                        const LinearProgressIndicator(),
                      if (file.status == FileStatus.finished)
                        Text('Saved: ${file.savedPath ?? "unknown"}', style: const TextStyle(color: Colors.green)),
                      if (file.status == FileStatus.failed)
                        Text('Error: ${file.errorMessage ?? "Unknown error"}', style: const TextStyle(color: Colors.red)),
                    ],
                  ),
                  trailing: isWaiting ? null : _getStatusIcon(file.status),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
  
  Future<void> _acceptFiles(
    BuildContext context,
    ReceiveProvider receiveProvider,
    ReceiveSession session,
  ) async {
    if (_selectedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one file')),
      );
      return;
    }
    
    // Call accept endpoint via HTTP client
    final httpClient = HttpClientService();
    final device = session.sender;
    
    final tokens = await httpClient.getFileTokens(
      device: device,
      sessionId: session.sessionId,
      files: _selectedFiles.map((id) {
        final file = session.files[id]!.file;
        return FileInfo(
          id: id,
          fileName: file.fileName,
          size: file.size,
          fileType: file.fileType,
          mimeType: file.mimeType,
        );
      }).fold<Map<String, FileInfo>>({}, (map, file) {
        map[file.id] = file;
        return map;
      }),
    );
    
    if (tokens == null || tokens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to accept files')),
      );
      return;
    }
    
    // Update session status to receiving
    final updatedFiles = Map<String, ReceivingFile>.from(session.files);
    for (final fileId in _selectedFiles) {
      final file = updatedFiles[fileId];
      if (file != null) {
        updatedFiles[fileId] = file.copyWith(
          token: tokens[fileId],
          status: FileStatus.queue,
        );
      }
    }
    
    receiveProvider.startSession(ReceiveSession(
      sessionId: session.sessionId,
      sender: session.sender,
      files: updatedFiles,
      status: SessionStatus.receiving,
      startTime: DateTime.now(),
      destinationDirectory: session.destinationDirectory,
    ));
  }

  Widget _getFileIcon(FileType fileType) {
    switch (fileType) {
      case FileType.image:
        return const Icon(Icons.image);
      case FileType.video:
        return const Icon(Icons.video_file);
      case FileType.audio:
        return const Icon(Icons.audio_file);
      case FileType.text:
        return const Icon(Icons.text_snippet);
      default:
        return const Icon(Icons.insert_drive_file);
    }
  }

  Widget _getStatusIcon(FileStatus status) {
    switch (status) {
      case FileStatus.finished:
        return const Icon(Icons.check_circle, color: Colors.green);
      case FileStatus.failed:
        return const Icon(Icons.error, color: Colors.red);
      case FileStatus.sending:
      case FileStatus.receiving:
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
