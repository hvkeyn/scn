import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:scn/providers/send_provider.dart';
import 'package:scn/providers/device_provider.dart';
import 'package:scn/providers/receive_provider.dart';
import 'package:scn/services/http_client_service.dart';
import 'package:scn/services/app_service.dart';
import 'package:scn/models/device.dart';
import 'package:scn/models/file_info.dart';
import 'package:scn/models/session.dart';
import 'package:scn/utils/file_opener.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';

class SendTab extends StatelessWidget {
  const SendTab({super.key});

  @override
  Widget build(BuildContext context) {
    final sendProvider = context.watch<SendProvider>();
    final deviceProvider = context.watch<DeviceProvider>();
    
    return sendProvider.currentSession != null
        ? _buildSessionView(context, sendProvider)
        : _buildMainView(context, sendProvider, deviceProvider);
  }

  Widget _buildMainView(
    BuildContext context,
    SendProvider sendProvider,
    DeviceProvider deviceProvider,
  ) {
    final receiveProvider = context.watch<ReceiveProvider>();
    
    return Column(
      children: [
        // Selected Files Section
        if (sendProvider.selectedFiles.isNotEmpty) 
          _buildSelectedFilesCard(context, sendProvider),
        
        // Main Content
        Expanded(
          child: sendProvider.selectedFiles.isEmpty
              ? _buildEmptyStateWithHistory(context, sendProvider, receiveProvider)
              : _buildDeviceList(context, sendProvider, deviceProvider),
        ),
        
        // Bottom Action Bar
        if (sendProvider.selectedFiles.isEmpty)
          _buildAddFilesButton(context, sendProvider),
      ],
    );
  }
  
  Widget _buildEmptyStateWithHistory(
    BuildContext context, 
    SendProvider sendProvider,
    ReceiveProvider receiveProvider,
  ) {
    final hasSentHistory = sendProvider.history.isNotEmpty;
    final hasReceivedHistory = receiveProvider.history.isNotEmpty;
    final hasHistory = hasSentHistory || hasReceivedHistory;
    
    if (!hasHistory) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Icon(
                Icons.upload_file,
                size: 50,
                color: Colors.white.withOpacity(0.3),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Send Files',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select files to share with nearby devices',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }
    
    // Show transfer history
    return CustomScrollView(
      slivers: [
        // Header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.history, color: Colors.white.withOpacity(0.7), size: 20),
                const SizedBox(width: 8),
                Text(
                  'Transfer History',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        
        // Sent files section
        if (hasSentHistory) ...[
          SliverToBoxAdapter(
            child: _buildSectionHeader(context, 'Sent', Icons.upload, sendProvider.history.length),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final session = sendProvider.history[index];
                return _buildHistoryItem(context, session, isSent: true);
              },
              childCount: sendProvider.history.take(10).length,
            ),
          ),
        ],
        
        // Received files section
        if (hasReceivedHistory) ...[
          SliverToBoxAdapter(
            child: _buildSectionHeader(context, 'Received', Icons.download, receiveProvider.history.length),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final session = receiveProvider.history[index];
                return _buildReceivedHistoryItem(context, session);
              },
              childCount: receiveProvider.history.take(10).length,
            ),
          ),
        ],
        
        // Bottom padding
        const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
      ],
    );
  }
  
  Widget _buildSectionHeader(BuildContext context, String title, IconData icon, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white54),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildHistoryItem(BuildContext context, SendSession session, {bool isSent = true}) {
    final fileCount = session.files.length;
    final successCount = session.files.values.where((f) => f.status == FileStatus.finished).length;
    final isSuccess = successCount == fileCount;
    final totalSize = session.files.values.fold<int>(0, (sum, f) => sum + f.file.size);
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: Colors.white.withOpacity(0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Status icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: (isSuccess ? Colors.green : Colors.orange).withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isSent ? Icons.upload : Icons.download,
                color: isSuccess ? Colors.green : Colors.orange,
              ),
            ),
            const SizedBox(width: 12),
            
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.target.alias,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$successCount/$fileCount files • ${_formatFileSize(totalSize)}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            
            // Time
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Icon(
                  isSuccess ? Icons.check_circle : Icons.warning,
                  color: isSuccess ? Colors.green : Colors.orange,
                  size: 18,
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTime(session.endTime ?? session.startTime ?? DateTime.now()),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildReceivedHistoryItem(BuildContext context, ReceiveSession session) {
    final fileCount = session.files.length;
    final successCount = session.files.values.where((f) => f.status == FileStatus.finished).length;
    final isSuccess = successCount == fileCount;
    final totalSize = session.files.values.fold<int>(0, (sum, f) => sum + f.file.size);
    
    // Get first saved file path for opening folder
    final savedFiles = session.files.values.where((f) => f.savedPath != null).toList();
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: Colors.white.withOpacity(0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showReceivedFilesDialog(context, session),
        onSecondaryTap: savedFiles.isNotEmpty 
            ? () => FileOpener.openFolder(savedFiles.first.savedPath!)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Status icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (isSuccess ? Colors.green : Colors.orange).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.download,
                  color: isSuccess ? Colors.green : Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'From ${session.sender.alias}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$successCount/$fileCount files • ${_formatFileSize(totalSize)}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Actions
              if (savedFiles.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.folder_open, color: Colors.white54, size: 20),
                  onPressed: () => FileOpener.openFolder(savedFiles.first.savedPath!),
                  tooltip: 'Open folder',
                ),
              
              // Time
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Icon(
                    isSuccess ? Icons.check_circle : Icons.warning,
                    color: isSuccess ? Colors.green : Colors.orange,
                    size: 18,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(session.endTime ?? session.startTime ?? DateTime.now()),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  void _showReceivedFilesDialog(BuildContext context, ReceiveSession session) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a1a2e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.download_done, color: Colors.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Received from ${session.sender.alias}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.folder_open, color: Colors.white70),
                  onPressed: () {
                    final savedFile = session.files.values.firstWhere(
                      (f) => f.savedPath != null,
                      orElse: () => session.files.values.first,
                    );
                    if (savedFile.savedPath != null) {
                      FileOpener.openFolder(savedFile.savedPath!);
                    }
                  },
                  tooltip: 'Open folder',
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white24),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: session.files.length,
              itemBuilder: (context, index) {
                final file = session.files.values.elementAt(index);
                return ListTile(
                  leading: Icon(
                    _getFileIcon(file.file.fileType),
                    color: _getFileColor(file.file.fileType),
                  ),
                  title: Text(
                    file.file.fileName,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    file.savedPath ?? 'Not saved',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: file.savedPath != null
                      ? IconButton(
                          icon: const Icon(Icons.open_in_new, color: Colors.white54),
                          onPressed: () => FileOpener.openFile(file.savedPath!),
                        )
                      : const Icon(Icons.error, color: Colors.red),
                  onTap: file.savedPath != null 
                      ? () => FileOpener.openFile(file.savedPath!)
                      : null,
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
  
  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return DateFormat('HH:mm').format(time);
    if (diff.inDays == 1) return 'Yesterday';
    return DateFormat('MMM d').format(time);
  }
  
  Widget _buildAddFilesButton(BuildContext context, SendProvider sendProvider) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _pickFiles(context, sendProvider),
          icon: const Icon(Icons.add_circle_outline),
          label: const Text('Select Files'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedFilesCard(BuildContext context, SendProvider sendProvider) {
    final totalSize = sendProvider.selectedFiles.fold<int>(
      0, (sum, file) => sum + file.size,
    );
    
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.folder_open, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${sendProvider.selectedFiles.length} file${sendProvider.selectedFiles.length > 1 ? 's' : ''} selected',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _formatFileSize(totalSize),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // Add more files
                IconButton(
                  icon: const Icon(Icons.add, color: Colors.white70),
                  onPressed: () => _pickFiles(context, sendProvider),
                ),
                // Clear all
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.white70),
                  onPressed: () => sendProvider.clearFiles(),
                ),
              ],
            ),
          ),
          
          // Files List (horizontal scroll)
          SizedBox(
            height: 90,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: sendProvider.selectedFiles.length,
              itemBuilder: (context, index) {
                final file = sendProvider.selectedFiles[index];
                return _buildFileChip(context, sendProvider, file);
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
  
  Widget _buildFileChip(BuildContext context, SendProvider sendProvider, FileInfo file) {
    return Container(
      width: 100,
      margin: const EdgeInsets.only(right: 8, bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _getFileIcon(file.fileType),
                  color: _getFileColor(file.fileType),
                  size: 28,
                ),
                const SizedBox(height: 4),
                Text(
                  file.fileName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                Text(
                  _formatFileSize(file.size),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          // Remove button
          Positioned(
            top: 0,
            right: 0,
            child: InkWell(
              onTap: () => sendProvider.removeFile(file.id),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.3),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(12),
                    bottomLeft: Radius.circular(8),
                  ),
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.red),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDeviceList(
    BuildContext context,
    SendProvider sendProvider,
    DeviceProvider deviceProvider,
  ) {
    if (deviceProvider.devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.wifi_find,
              size: 64,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No devices found',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Make sure devices are on the same network',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Send to',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: deviceProvider.devices.length,
            itemBuilder: (context, index) {
              final device = deviceProvider.devices[index];
              return _buildDeviceTile(context, sendProvider, device);
            },
          ),
        ),
      ],
    );
  }
  
  Widget _buildDeviceTile(BuildContext context, SendProvider sendProvider, Device device) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white.withOpacity(0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _sendFiles(context, sendProvider, device),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Device icon
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getDeviceIcon(device.type),
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 16),
              
              // Device info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.alias,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${device.ip}:${device.port}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Send button
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSessionView(BuildContext context, SendProvider sendProvider) {
    final session = sendProvider.currentSession!;
    final progress = sendProvider.overallProgress;
    final finished = sendProvider.countFilesByStatus(FileStatus.finished);
    final failed = sendProvider.countFilesByStatus(FileStatus.failed);
    final total = session.files.length;
    
    return Column(
      children: [
        // Header with progress
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            border: Border(
              bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // Target device
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getDeviceIcon(session.target.type),
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sending to ${session.target.alias}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$finished/$total files • ${(progress * 100).toInt()}%',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Cancel button
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => sendProvider.cancelSession(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: Colors.white.withOpacity(0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    failed > 0 ? Colors.orange : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // Files list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: session.files.length,
            itemBuilder: (context, index) {
              final fileEntry = session.files.entries.elementAt(index);
              final file = fileEntry.value;
              return _buildTransferFileTile(context, file);
            },
          ),
        ),
        
        // Done button (when finished)
        if (session.status == SessionStatus.finished ||
            session.status == SessionStatus.finishedWithErrors ||
            session.status == SessionStatus.cancelled)
          Container(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  sendProvider.finishSession();
                  sendProvider.clearFiles();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Done'),
              ),
            ),
          ),
      ],
    );
  }
  
  Widget _buildTransferFileTile(BuildContext context, SendingFile file) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white.withOpacity(0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // File icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _getFileColor(file.file.fileType).withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _getFileIcon(file.file.fileType),
                color: _getFileColor(file.file.fileType),
              ),
            ),
            const SizedBox(width: 12),
            
            // File info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.file.fileName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        _formatFileSize(file.file.size),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 12,
                        ),
                      ),
                      if (file.status == FileStatus.sending) ...[
                        const SizedBox(width: 8),
                        Text(
                          '${(file.progress * 100).toInt()}%',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                  // Progress bar for sending files
                  if (file.status == FileStatus.sending) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: file.progress,
                        minHeight: 4,
                        backgroundColor: Colors.white.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            
            // Status icon
            _buildStatusIndicator(context, file.status),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatusIndicator(BuildContext context, FileStatus status) {
    switch (status) {
      case FileStatus.finished:
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check, color: Colors.green, size: 20),
        );
      case FileStatus.failed:
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.close, color: Colors.red, size: 20),
        );
      case FileStatus.sending:
        return SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).colorScheme.primary,
            ),
          ),
        );
      case FileStatus.queue:
        return Icon(Icons.schedule, color: Colors.white.withOpacity(0.5), size: 24);
      case FileStatus.skipped:
        return Icon(Icons.skip_next, color: Colors.orange.withOpacity(0.7), size: 24);
      default:
        return Icon(Icons.pending, color: Colors.white.withOpacity(0.5), size: 24);
    }
  }

  Future<void> _pickFiles(BuildContext context, SendProvider sendProvider) async {
    final result = await file_picker.FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: file_picker.FileType.any,
    );
    
    if (result != null && result.files.isNotEmpty) {
      for (final platformFile in result.files) {
        final fileInfo = FileInfo(
          id: const Uuid().v4(),
          fileName: platformFile.name,
          size: platformFile.size,
          fileType: _getFileTypeFromName(platformFile.name),
          mimeType: platformFile.extension,
        );
        
        sendProvider.addFile(fileInfo, localPath: platformFile.path);
      }
    }
  }

  Future<void> _sendFiles(
    BuildContext context,
    SendProvider sendProvider,
    Device device,
  ) async {
    if (sendProvider.selectedFiles.isEmpty) return;
    
    final appService = context.read<AppService>();
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
        alias: appService.deviceAlias,
        version: '1.0.0',
      );
      
      if (remoteSessionId == null) {
        _showError(context, 'Failed to connect to ${device.alias}');
        sendProvider.cancelSession();
        return;
      }
      
      // Get file tokens (accept files)
      final tokens = await httpClient.getFileTokens(
        device: device,
        sessionId: remoteSessionId,
        files: sendingFiles.map((key, value) => MapEntry(key, value.file)),
      );
      
      if (tokens == null || tokens.isEmpty) {
        _showError(context, 'Transfer rejected by ${device.alias}');
        sendProvider.cancelSession();
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
      
      // Send files one by one
      int successCount = 0;
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
            sendProvider.updateFileProgress(
              entry.key,
              progress,
              (progress * file.file.size).toInt(),
            );
          },
        );
        
        if (success) {
          sendProvider.updateFileStatus(entry.key, FileStatus.finished);
          successCount++;
        } else {
          sendProvider.updateFileStatus(
            entry.key,
            FileStatus.failed,
            errorMessage: 'Upload failed',
          );
        }
      }
      
      // Update session status
      sendProvider.startSession(SendSession(
        sessionId: sessionId,
        target: device,
        files: sendProvider.currentSession!.files,
        status: successCount == updatedFiles.length 
            ? SessionStatus.finished 
            : SessionStatus.finishedWithErrors,
        startTime: sendProvider.currentSession!.startTime,
        endTime: DateTime.now(),
      ));
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              successCount == updatedFiles.length
                  ? 'Files sent to ${device.alias}'
                  : '$successCount/${updatedFiles.length} files sent',
            ),
            backgroundColor: successCount == updatedFiles.length 
                ? Colors.green 
                : Colors.orange,
          ),
        );
      }
    } catch (e) {
      _showError(context, 'Error: $e');
      sendProvider.cancelSession();
    }
  }
  
  void _showError(BuildContext context, String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
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
  
  Color _getFileColor(FileType type) {
    switch (type) {
      case FileType.image:
        return Colors.pink;
      case FileType.video:
        return Colors.purple;
      case FileType.audio:
        return Colors.orange;
      case FileType.text:
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  FileType _getFileTypeFromName(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'].contains(ext)) return FileType.image;
    if (['mp4', 'avi', 'mov', 'mkv', 'webm', 'flv'].contains(ext)) return FileType.video;
    if (['mp3', 'wav', 'ogg', 'flac', 'aac', 'm4a'].contains(ext)) return FileType.audio;
    if (['txt', 'md', 'json', 'xml', 'html', 'css', 'js'].contains(ext)) return FileType.text;
    return FileType.other;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
