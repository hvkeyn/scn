import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scn/providers/receive_provider.dart';
import 'package:scn/providers/device_provider.dart';
import 'package:scn/providers/remote_peer_provider.dart';
import 'package:scn/services/app_service.dart';
import 'package:scn/services/http_client_service.dart';
import 'package:scn/models/session.dart';
import 'package:scn/models/file_info.dart';
import 'package:scn/models/device_visibility.dart';
import 'package:scn/models/remote_peer.dart';
import 'package:scn/models/device.dart';
import 'package:scn/widgets/scn_logo.dart';
import 'package:scn/widgets/add_peer_dialog.dart';
import 'package:scn/widgets/invitation_card.dart';
import 'package:scn/widgets/peer_tile.dart';

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
    return Consumer<RemotePeerProvider>(
      builder: (context, peerProvider, _) {
        final invitations = peerProvider.pendingInvitations;
        final connectedPeers = peerProvider.connectedPeers;
        final allPeers = peerProvider.peers;
        
        return CustomScrollView(
          slivers: [
            // Header with logo and device info
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 40, 32, 24),
                child: Column(
                  children: [
                    // Large SCN Logo
                    const SCNLogo(size: 100),
                    const SizedBox(height: 24),
                    // Device Name
                    Text(
                      appService.deviceAlias,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Status Row
                    _buildStatusRow(context, appService, connectedPeers.length),
                    const SizedBox(height: 24),
                    // Visibility Buttons
                    _buildVisibilitySection(context, appService),
                  ],
                ),
              ),
            ),
            
            // Pending Invitations
            if (invitations.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _buildSectionHeader(
                  context, 
                  'Incoming Connections',
                  Icons.person_add,
                  badgeCount: invitations.length,
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final invitation = invitations[index];
                    return InvitationCard(
                      invitation: invitation,
                      onAccept: (password) async {
                        final meshService = appService.meshService;
                        await meshService?.acceptInvitation(invitation, password: password);
                      },
                      onReject: () {
                        final meshService = appService.meshService;
                        meshService?.rejectInvitation(invitation);
                      },
                    );
                  },
                  childCount: invitations.length,
                ),
              ),
            ],
            
            // Connected Peers Section
            if (connectedPeers.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _buildSectionHeader(
                  context, 
                  'Connected Peers',
                  Icons.link,
                  badgeCount: connectedPeers.length,
                  badgeColor: Colors.green,
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final peer = connectedPeers[index];
                    return PeerTile(
                      peer: peer,
                      onDisconnect: () {
                        appService.meshService?.disconnectPeer(peer.id);
                      },
                      onToggleFavorite: () {
                        peerProvider.toggleFavorite(peer.id);
                      },
                      onRemove: () {
                        _confirmRemovePeer(context, peerProvider, peer);
                      },
                    );
                  },
                  childCount: connectedPeers.length,
                ),
              ),
            ],
            
            // Local Network Devices (from discovery)
            Consumer<DeviceProvider>(
              builder: (context, deviceProvider, _) {
                final localDevices = deviceProvider.devices;
                if (localDevices.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
                
                return SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader(
                        context, 
                        'Local Network',
                        Icons.wifi,
                        badgeCount: localDevices.length,
                        badgeColor: Colors.blue,
                      ),
                      ...localDevices.map((device) => _buildLocalDeviceTile(context, device)),
                    ],
                  ),
                );
              },
            ),
            
            // All Saved Peers
            if (allPeers.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _buildSectionHeader(
                  context, 
                  'Saved Peers',
                  Icons.devices,
                  action: IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: Colors.white70),
                    onPressed: () => _showAddPeerDialog(context, appService),
                    tooltip: 'Add Remote Peer',
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final peer = allPeers[index];
                    // Skip already connected peers (shown above)
                    if (peer.status == PeerStatus.connected) {
                      return const SizedBox.shrink();
                    }
                    return PeerTile(
                      peer: peer,
                      onConnect: () async {
                        await appService.meshService?.connectToAddress(
                          address: peer.address,
                          port: peer.port,
                        );
                      },
                      onToggleFavorite: () {
                        peerProvider.toggleFavorite(peer.id);
                      },
                      onRemove: () {
                        _confirmRemovePeer(context, peerProvider, peer);
                      },
                    );
                  },
                  childCount: allPeers.length,
                ),
              ),
            ],
            
            // Empty state - Add first peer
            if (allPeers.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: _buildEmptyState(context, appService),
                ),
              ),
            
            // Server info card
            if (appService.running)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _buildServerInfoCard(context, appService),
                ),
              ),
            
            // Bottom padding
            const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
          ],
        );
      },
    );
  }

  Widget _buildStatusRow(BuildContext context, AppService appService, int connectedCount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Online status
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: appService.running 
                ? Colors.green.withOpacity(0.2)
                : Colors.grey.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: appService.running 
                  ? Colors.green.withOpacity(0.5)
                  : Colors.grey.withOpacity(0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                appService.running ? Icons.wifi : Icons.wifi_off,
                size: 14,
                color: appService.running ? Colors.green : Colors.grey,
              ),
              const SizedBox(width: 6),
              Text(
                appService.running ? 'Online' : 'Offline',
                style: TextStyle(
                  fontSize: 12,
                  color: appService.running ? Colors.green : Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        
        if (connectedCount > 0) ...[
          const SizedBox(width: 8),
          // Connected peers badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.people,
                  size: 14,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  '$connectedCount peers',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildVisibilitySection(BuildContext context, AppService appService) {
    return Column(
      children: [
        Text(
          'Quick Save',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildVisibilityButton(
              context,
              appService,
              DeviceVisibility.disabled,
              'Off',
              Icons.visibility_off,
            ),
            const SizedBox(width: 8),
            _buildVisibilityButton(
              context,
              appService,
              DeviceVisibility.favorites,
              'Favorites',
              Icons.star,
            ),
            const SizedBox(width: 8),
            _buildVisibilityButton(
              context,
              appService,
              DeviceVisibility.enabled,
              'Everyone',
              Icons.public,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVisibilityButton(
    BuildContext context,
    AppService appService,
    DeviceVisibility visibility,
    String label,
    IconData icon,
  ) {
    final isSelected = appService.deviceVisibility == visibility;
    final theme = Theme.of(context);
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => appService.setDeviceVisibility(visibility),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected 
                ? theme.colorScheme.primary 
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected 
                  ? theme.colorScheme.primary 
                  : Colors.white.withOpacity(0.2),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.white : Colors.white70,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, 
    String title, 
    IconData icon, {
    int? badgeCount,
    Color? badgeColor,
    Widget? action,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white54),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          if (badgeCount != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: (badgeColor ?? Theme.of(context).colorScheme.primary).withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$badgeCount',
                style: TextStyle(
                  color: badgeColor ?? Theme.of(context).colorScheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (action != null) action,
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppService appService) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.add_link,
            size: 36,
            color: Colors.white.withOpacity(0.3),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'No peers connected',
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Add a remote peer to start sharing files\nacross the network',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.4),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () => _showAddPeerDialog(context, appService),
          icon: const Icon(Icons.add),
          label: const Text('Add Remote Peer'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLocalDeviceTile(BuildContext context, Device device) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        color: Colors.white.withOpacity(0.05),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              device.type == DeviceType.mobile ? Icons.phone_android : Icons.computer,
              color: Colors.blue,
            ),
          ),
          title: Text(
            device.alias,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            '${device.ip}:${device.port}',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Local',
              style: TextStyle(color: Colors.green, fontSize: 11),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildServerInfoCard(BuildContext context, AppService appService) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.dns, color: Colors.green, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Server Running',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
              Text(
                'Port ${appService.port}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showAddPeerDialog(BuildContext context, AppService appService) async {
    final result = await AddPeerDialog.show(context);
    if (result != null && mounted) {
      final success = await appService.meshService?.connectToAddress(
        address: result.address,
        port: result.port,
        password: result.password,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success == true 
                  ? 'Connecting to ${result.address}...'
                  : 'Failed to connect to ${result.address}',
            ),
            backgroundColor: success == true ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  void _confirmRemovePeer(
    BuildContext context, 
    RemotePeerProvider provider, 
    RemotePeer peer,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text('Remove Peer', style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove "${peer.alias}" from saved peers?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              provider.removePeer(peer.id);
              Navigator.pop(context);
            },
            child: Text('Remove', style: TextStyle(color: Colors.red.shade300)),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionView(BuildContext context, ReceiveSession session) {
    final receiveProvider = context.watch<ReceiveProvider>();
    final isWaiting = session.status == SessionStatus.waiting;
    
    return Column(
      children: [
        AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
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
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white70,
              ),
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
              
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
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
                  title: Text(
                    file.desiredName ?? file.file.fileName,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatFileSize(file.file.size),
                        style: TextStyle(color: Colors.white.withOpacity(0.5)),
                      ),
                      if (file.status == FileStatus.sending || file.status == FileStatus.receiving)
                        const LinearProgressIndicator(),
                      if (file.status == FileStatus.finished)
                        Text(
                          'Saved: ${file.savedPath ?? "unknown"}', 
                          style: const TextStyle(color: Colors.green, fontSize: 12),
                        ),
                      if (file.status == FileStatus.failed)
                        Text(
                          'Error: ${file.errorMessage ?? "Unknown error"}', 
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                        ),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to accept files')),
        );
      }
      return;
    }
    
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
    final color = Colors.white70;
    switch (fileType) {
      case FileType.image:
        return Icon(Icons.image, color: color);
      case FileType.video:
        return Icon(Icons.video_file, color: color);
      case FileType.audio:
        return Icon(Icons.audio_file, color: color);
      case FileType.text:
        return Icon(Icons.text_snippet, color: color);
      default:
        return Icon(Icons.insert_drive_file, color: color);
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
        return Icon(Icons.pending, color: Colors.white.withOpacity(0.5));
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
