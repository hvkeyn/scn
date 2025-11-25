import 'package:flutter/material.dart';
import 'package:scn/models/remote_peer.dart';

/// Tile widget for displaying a peer in the list
class PeerTile extends StatelessWidget {
  final RemotePeer peer;
  final VoidCallback? onTap;
  final VoidCallback? onConnect;
  final VoidCallback? onDisconnect;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onRemove;
  
  const PeerTile({
    super.key,
    required this.peer,
    this.onTap,
    this.onConnect,
    this.onDisconnect,
    this.onToggleFavorite,
    this.onRemove,
  });

  Color _getStatusColor() {
    switch (peer.status) {
      case PeerStatus.connected:
        return Colors.green;
      case PeerStatus.connecting:
        return Colors.orange;
      case PeerStatus.error:
        return Colors.red;
      case PeerStatus.disconnected:
        return Colors.grey;
    }
  }

  IconData _getTypeIcon() {
    switch (peer.type) {
      case PeerType.local:
        return Icons.wifi;
      case PeerType.remote:
        return Icons.public;
    }
  }

  String _getStatusText() {
    switch (peer.status) {
      case PeerStatus.connected:
        return 'Connected';
      case PeerStatus.connecting:
        return 'Connecting...';
      case PeerStatus.error:
        return peer.errorMessage ?? 'Error';
      case PeerStatus.disconnected:
        return 'Offline';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _getStatusColor();
    final isOnline = peer.status == PeerStatus.connected;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isOnline 
            ? statusColor.withOpacity(0.05)
            : Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOnline 
              ? statusColor.withOpacity(0.3)
              : Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // Status indicator & Icon
                Stack(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _getTypeIcon(),
                        color: statusColor,
                        size: 22,
                      ),
                    ),
                    // Online indicator
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF1a1a2e),
                            width: 2,
                          ),
                        ),
                        child: peer.status == PeerStatus.connecting
                            ? const Padding(
                                padding: EdgeInsets.all(2),
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  valueColor: AlwaysStoppedAnimation(Colors.white),
                                ),
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              peer.alias,
                              style: TextStyle(
                                color: Colors.white.withOpacity(isOnline ? 1.0 : 0.7),
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (peer.isFavorite) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.star,
                              color: Colors.amber,
                              size: 14,
                            ),
                          ],
                          if (peer.type == PeerType.remote) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'REMOTE',
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            '${peer.address}:${peer.port}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _getStatusText(),
                            style: TextStyle(
                              color: statusColor.withOpacity(0.8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // Actions
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Favorite button
                    if (onToggleFavorite != null)
                      IconButton(
                        onPressed: onToggleFavorite,
                        icon: Icon(
                          peer.isFavorite ? Icons.star : Icons.star_border,
                          color: peer.isFavorite 
                              ? Colors.amber 
                              : Colors.white.withOpacity(0.3),
                          size: 20,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        padding: EdgeInsets.zero,
                        tooltip: peer.isFavorite ? 'Remove from favorites' : 'Add to favorites',
                      ),
                    
                    // Connect/Disconnect button
                    if (peer.status == PeerStatus.connected && onDisconnect != null)
                      IconButton(
                        onPressed: onDisconnect,
                        icon: Icon(
                          Icons.link_off,
                          color: Colors.red.withOpacity(0.7),
                          size: 20,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        padding: EdgeInsets.zero,
                        tooltip: 'Disconnect',
                      )
                    else if (peer.status == PeerStatus.disconnected && onConnect != null)
                      IconButton(
                        onPressed: onConnect,
                        icon: Icon(
                          Icons.link,
                          color: theme.colorScheme.primary.withOpacity(0.7),
                          size: 20,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        padding: EdgeInsets.zero,
                        tooltip: 'Connect',
                      ),
                    
                    // More actions
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        switch (value) {
                          case 'remove':
                            onRemove?.call();
                            break;
                          case 'connect':
                            onConnect?.call();
                            break;
                          case 'disconnect':
                            onDisconnect?.call();
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        if (peer.status == PeerStatus.disconnected && onConnect != null)
                          const PopupMenuItem(
                            value: 'connect',
                            child: Row(
                              children: [
                                Icon(Icons.link, size: 18),
                                SizedBox(width: 8),
                                Text('Connect'),
                              ],
                            ),
                          ),
                        if (peer.status == PeerStatus.connected && onDisconnect != null)
                          const PopupMenuItem(
                            value: 'disconnect',
                            child: Row(
                              children: [
                                Icon(Icons.link_off, size: 18),
                                SizedBox(width: 8),
                                Text('Disconnect'),
                              ],
                            ),
                          ),
                        if (onRemove != null)
                          PopupMenuItem(
                            value: 'remove',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300),
                                const SizedBox(width: 8),
                                Text('Remove', style: TextStyle(color: Colors.red.shade300)),
                              ],
                            ),
                          ),
                      ],
                      icon: Icon(
                        Icons.more_vert,
                        color: Colors.white.withOpacity(0.4),
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

