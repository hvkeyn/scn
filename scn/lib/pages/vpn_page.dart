import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:scn/services/mesh_network_service.dart';
import 'package:scn/services/app_service.dart';
import 'package:scn/services/peer_discovery_service.dart';
import 'package:scn/services/stun_service.dart';
import 'package:scn/models/remote_peer.dart';

/// VPN / Mesh Network Management Page
class VpnPage extends StatefulWidget {
  const VpnPage({super.key});

  @override
  State<VpnPage> createState() => _VpnPageState();
}

class _VpnPageState extends State<VpnPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _portController = TextEditingController(text: '53318');
  final TextEditingController _passwordController = TextEditingController();
  
  NatInfo? _natInfo;
  InviteCode? _myInviteCode;
  bool _isDiscovering = false;
  bool _isConnecting = false;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _discoverNat();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    _addressController.dispose();
    _portController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
  
  Future<void> _discoverNat() async {
    setState(() => _isDiscovering = true);
    
    final appService = context.read<AppService>();
    final localPort = appService.port ?? 53317;
    
    // Try to discover public IP
    try {
      final stun = StunService();
      _natInfo = await stun.discoverNat(localPort: localPort);
      debugPrint('STUN result: publicIp=${_natInfo?.publicIp}, publicPort=${_natInfo?.publicPort}');
    } catch (e) {
      debugPrint('STUN failed: $e');
      _natInfo = null;
    }
    
    // Generate invite code - ALWAYS use current _natInfo
    final publicIp = _natInfo?.publicIp;
    final publicPort = _natInfo?.publicPort;
    
    debugPrint('Creating invite with: publicIp=$publicIp, publicPort=$publicPort, localPort=$localPort');
    
    _myInviteCode = InviteCode(
      deviceId: appService.deviceId,
      deviceAlias: appService.deviceAlias,
      publicIp: publicIp,
      publicPort: publicPort,
      localPort: localPort,
      secret: _generateSecret(),
      natType: _natInfo?.natType ?? NatType.unknown,
    );
    
    debugPrint('Invite URL: ${_myInviteCode?.toUrl()}');
    
    setState(() => _isDiscovering = false);
  }
  
  String _generateSecret() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    return base64Encode(bytes).replaceAll(RegExp(r'[+/=]'), '');
  }
  
  Future<void> _connectToPeer() async {
    final address = _addressController.text.trim();
    final port = int.tryParse(_portController.text) ?? 53318;
    final password = _passwordController.text.isNotEmpty 
        ? _passwordController.text 
        : null;
    
    if (address.isEmpty) {
      _showError('Enter peer address');
      return;
    }
    
    setState(() => _isConnecting = true);
    
    try {
      final appService = context.read<AppService>();
      final success = await appService.meshService?.connectToAddress(
        address: address,
        port: port,
        password: password,
      ) ?? false;
      
      if (success) {
        _showSuccess('Connected successfully!');
        _addressController.clear();
        _passwordController.clear();
      } else {
        _showError('Connection failed');
      }
    } catch (e) {
      _showError('Error: $e');
    }
    
    setState(() => _isConnecting = false);
  }
  
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
  
  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesh VPN'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.share), text: 'Share'),
            Tab(icon: Icon(Icons.add_link), text: 'Connect'),
            Tab(icon: Icon(Icons.people), text: 'Peers'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildShareTab(),
          _buildConnectTab(),
          _buildPeersTab(),
        ],
      ),
    );
  }
  
  Widget _buildShareTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // NAT Status Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _natInfo != null ? Icons.check_circle : Icons.error,
                        color: _natInfo != null ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Network Status',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      if (_isDiscovering)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: _discoverNat,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_natInfo != null) ...[
                    _buildInfoRow('Public IP', _natInfo!.publicIp),
                    _buildInfoRow('Public Port', _natInfo!.publicPort.toString()),
                    _buildInfoRow('NAT Type', _getNatTypeName(_natInfo!.natType)),
                  ] else if (!_isDiscovering) ...[
                    const Text(
                      'Could not determine public IP. You may be behind a restrictive firewall.',
                      style: TextStyle(color: Colors.orange),
                    ),
                  ],
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Invite Code Card
          if (_myInviteCode != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your Invite Code',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        _myInviteCode!.toShortCode(),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.copy),
                            label: const Text('Copy Code'),
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: _myInviteCode!.toShortCode()),
                              );
                              _showSuccess('Code copied!');
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.link),
                            label: const Text('Copy URL'),
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: _myInviteCode!.toUrl()),
                              );
                              _showSuccess('URL copied!');
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      icon: const Icon(Icons.qr_code),
                      label: const Text('Show QR Code'),
                      onPressed: () => _showQrDialog(),
                    ),
                  ],
                ),
              ),
            ),
          
          const SizedBox(height: 16),
          
          // How it works
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How P2P VPN Works',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  _buildStep(1, 'Share your invite code with a friend'),
                  _buildStep(2, 'They enter your code in the Connect tab'),
                  _buildStep(3, 'Direct encrypted connection is established'),
                  _buildStep(4, 'Transfer files securely over the internet'),
                  const SizedBox(height: 8),
                  const Text(
                    '🔒 All traffic is encrypted and disguised as HTTPS',
                    style: TextStyle(color: Colors.green),
                  ),
                  const Text(
                    '🌐 Works even behind NAT and firewalls',
                    style: TextStyle(color: Colors.blue),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildConnectTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Connect to Peer',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: 'IP Address or Invite Code',
                      hintText: 'e.g., 123.45.67.89 or scn://...',
                      prefixIcon: Icon(Icons.computer),
                    ),
                    onSubmitted: (_) => _connectToPeer(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _portController,
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      hintText: '53318',
                      prefixIcon: Icon(Icons.numbers),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Password (optional)',
                      hintText: 'Enter if peer requires password',
                      prefixIcon: Icon(Icons.lock),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    icon: _isConnecting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.link),
                    label: Text(_isConnecting ? 'Connecting...' : 'Connect'),
                    onPressed: _isConnecting ? null : _connectToPeer,
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Paste Invite Code',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  const Text('Paste a friend\'s invite code or URL'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.content_paste),
                          label: const Text('Paste from Clipboard'),
                          onPressed: () async {
                            final data = await Clipboard.getData(Clipboard.kTextPlain);
                            if (data?.text != null && data!.text!.isNotEmpty) {
                              _addressController.text = data.text!;
                              _showSuccess('Code pasted! Press Connect to continue.');
                            } else {
                              _showError('Clipboard is empty');
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '📱 QR scanner available only on mobile devices',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Connection Tips
          Card(
            color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.lightbulb,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Connection Tips',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('• If connection fails, try disabling VPN/firewall'),
                  const Text('• Symmetric NAT may require a relay server'),
                  const Text('• Use mobile hotspot for easier P2P connections'),
                  const Text('• Traffic is encrypted and looks like HTTPS'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildPeersTab() {
    return Consumer<AppService>(
      builder: (context, appService, child) {
        final peers = (appService.meshService?.connectedPeers ?? []);
        
        if (peers.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.people_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  'No connected peers',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Connect to peers using the Connect tab'),
              ],
            ),
          );
        }
        
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: peers.length,
          itemBuilder: (context, index) {
            final peer = peers[index];
            return _buildPeerCard(peer);
          },
        );
      },
    );
  }
  
  Widget _buildPeerCard(RemotePeer peer) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getStatusColor(peer.status),
          child: Icon(
            peer.type == PeerType.local ? Icons.wifi : Icons.language,
            color: Colors.white,
          ),
        ),
        title: Text(peer.alias),
        subtitle: Text('${peer.address}:${peer.port}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getStatusColor(peer.status).withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                peer.status.name.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  color: _getStatusColor(peer.status),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            PopupMenuButton<String>(
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'info',
                  child: Row(
                    children: [
                      Icon(Icons.info_outline),
                      SizedBox(width: 8),
                      Text('Details'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'disconnect',
                  child: Row(
                    children: [
                      Icon(Icons.link_off, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Disconnect', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
              onSelected: (value) {
                if (value == 'disconnect') {
                  context.read<AppService>().meshService?.disconnectPeer(peer.id);
                } else if (value == 'info') {
                  _showPeerInfo(peer);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
  
  void _showPeerInfo(RemotePeer peer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(peer.alias),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Address', '${peer.address}:${peer.port}'),
            _buildInfoRow('Type', peer.type.name),
            _buildInfoRow('Status', peer.status.name),
            if (peer.fingerprint != null)
              _buildInfoRow('Fingerprint', peer.fingerprint!.substring(0, 12)),
            if (peer.lastSeen != null)
              _buildInfoRow('Last seen', _formatTime(peer.lastSeen!)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
  
  void _showQrDialog() {
    if (_myInviteCode == null) {
      _showError('No invite code available');
      return;
    }
    
    final qrData = _myInviteCode!.toUrl();
    debugPrint('QR Data: $qrData');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your QR Code'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 220,
                height: 220,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 200,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.L,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade800,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SelectableText(
                  qrData,
                  style: const TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Scan this QR or copy the URL above',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: qrData));
              Navigator.pop(context);
              _showSuccess('URL copied!');
            },
            child: const Text('Copy URL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStep(int number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            child: Text(
              number.toString(),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
  
  String _getNatTypeName(NatType type) {
    switch (type) {
      case NatType.openInternet:
        return 'Open (No NAT)';
      case NatType.fullCone:
        return 'Full Cone (Easy P2P)';
      case NatType.restrictedCone:
        return 'Restricted Cone';
      case NatType.portRestricted:
        return 'Port Restricted';
      case NatType.symmetric:
        return 'Symmetric (Hard P2P)';
      case NatType.unknown:
        return 'Unknown';
    }
  }
  
  Color _getStatusColor(PeerStatus status) {
    switch (status) {
      case PeerStatus.connected:
        return Colors.green;
      case PeerStatus.connecting:
        return Colors.orange;
      case PeerStatus.disconnected:
        return Colors.grey;
      case PeerStatus.error:
        return Colors.red;
    }
  }
  
  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

