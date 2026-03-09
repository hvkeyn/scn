import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:scn/models/remote_peer.dart';
import 'package:scn/providers/remote_peer_provider.dart';
import 'package:scn/services/app_service.dart';
import 'package:scn/services/internet_transport_planner.dart';
import 'package:scn/services/mesh_network_service.dart';
import 'package:scn/services/network_diagnostics_service.dart';
import 'package:scn/services/peer_discovery_service.dart';
import 'package:scn/services/stun_service.dart';

class VpnPage extends StatefulWidget {
  const VpnPage({super.key});

  @override
  State<VpnPage> createState() => _VpnPageState();
}

class _VpnPageState extends State<VpnPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  NetworkDiagnosticsResult? _diagnostics;
  InviteCode? _inviteCode;
  bool _isRefreshing = false;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshInternetState();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _inputController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _refreshInternetState() async {
    final appService = context.read<AppService>();
    final mesh = appService.meshService;
    if (mesh == null) return;

    setState(() => _isRefreshing = true);
    try {
      final diagnostics = await mesh.runNetworkDiagnostics(localPort: mesh.port);
      final invite = await mesh.createInternetInvite(
        password: _passwordController.text.trim().isEmpty
            ? null
            : _passwordController.text.trim(),
      );

      if (!mounted) return;
      setState(() {
        _diagnostics = diagnostics;
        _inviteCode = invite;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _diagnostics = mesh.lastDiagnostics;
        _inviteCode = null;
      });
      _showSnack(
        'Не удалось создать invite через signaling: $e',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  Future<void> _connect() async {
    final appService = context.read<AppService>();
    final peerProvider = context.read<RemotePeerProvider>();
    final mesh = appService.meshService;
    if (mesh == null) return;

    final parser = PeerDiscoveryService(
      deviceId: appService.deviceId,
      deviceAlias: appService.deviceAlias,
    );
    final rawInput = _inputController.text.trim();
    if (rawInput.isEmpty) {
      _showSnack('Введите invite token, URL или legacy адрес', isError: true);
      return;
    }

    final manualPassword = _passwordController.text.trim();
    final invite = parser.parseInviteCode(rawInput);
    setState(() => _isConnecting = true);

    try {
      bool success = false;
      if (invite != null) {
        final resolvedInvite =
            _resolveInvite(invite, peerProvider.settings.signalingServerUrl);
        success = await mesh.connectWithInvite(
          resolvedInvite,
          password: manualPassword.isNotEmpty ? manualPassword : invite.password,
        );
      } else if (peerProvider.settings.enableLegacyDirect) {
        final parts = rawInput.split(':');
        final address = parts.first;
        final port = parts.length > 1 ? int.tryParse(parts[1]) ?? 53318 : 53318;
        success = await mesh.connectToAddress(
          address: address,
          port: port,
          password: manualPassword.isNotEmpty ? manualPassword : null,
        );
      } else {
        _showSnack(
          'Legacy direct path отключен. Используйте invite token через signaling.',
          isError: true,
        );
      }

      if (!mounted) return;
      if (success) {
        _showSnack('Соединение инициировано. Статус появится на вкладке Peers.');
        _inputController.clear();
      } else {
        _showSnack('Не удалось установить соединение', isError: true);
      }
    } catch (e) {
      _showSnack('Ошибка подключения: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  InviteCode _resolveInvite(InviteCode invite, String fallbackSignalingServerUrl) {
    if (!invite.usesSignalingSession &&
        invite.transportKind != InviteTransportKind.signalingSession) {
      return invite;
    }

    return InviteCode(
      deviceId: invite.deviceId,
      deviceAlias: invite.deviceAlias,
      publicIp: invite.publicIp,
      publicPort: invite.publicPort,
      localPort: invite.localPort,
      password: invite.password,
      secret: invite.secret,
      expiresAt: invite.expiresAt,
      natType: invite.natType,
      transportKind: invite.transportKind,
      signalingServerUrl:
          invite.signalingServerUrl ?? fallbackSignalingServerUrl,
      sessionId: invite.sessionId,
      inviteToken: invite.inviteToken,
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppService, RemotePeerProvider>(
      builder: (context, appService, peerProvider, _) {
        final mesh = appService.meshService;
        final peers = mesh?.connectedPeers ?? const <RemotePeer>[];
        final transportPlan = mesh?.currentTransportPlan ??
            const InternetTransportPlan(
              controlTransport: PeerTransport.unknown,
              fileTransportMode:
                  InternetFileTransportMode.webRtcDataChannelPlanned,
              summary: 'Нет активного WAN-транспорта',
              details: 'Сначала создайте или примите invite.',
            );

        return Scaffold(
          appBar: AppBar(
            title: const Text('Internet P2P'),
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.share), text: 'Share'),
                Tab(icon: Icon(Icons.link), text: 'Connect'),
                Tab(icon: Icon(Icons.people), text: 'Peers'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildShareTab(appService, peerProvider.settings, mesh, transportPlan),
              _buildConnectTab(appService, peerProvider.settings),
              _buildPeersTab(appService, peers),
            ],
          ),
        );
      },
    );
  }

  Widget _buildShareTab(
    AppService appService,
    NetworkSettings settings,
    MeshNetworkService? mesh,
    InternetTransportPlan transportPlan,
  ) {
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
                  Row(
                    children: [
                      Icon(
                        _diagnostics == null
                            ? Icons.help_outline
                            : _reachabilityIcon(_diagnostics!.reachability),
                        color: _diagnostics == null
                            ? Colors.grey
                            : _reachabilityColor(_diagnostics!.reachability),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Internet Readiness',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (_isRefreshing)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        IconButton(
                          onPressed: _refreshInternetState,
                          icon: const Icon(Icons.refresh),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_diagnostics != null) ...[
                    _buildInfoRow('Summary', _diagnostics!.summary),
                    _buildInfoRow('Recommendation', _diagnostics!.recommendation),
                    if (_diagnostics!.natInfo != null) ...[
                      _buildInfoRow('Public IP', _diagnostics!.natInfo!.publicIp),
                      _buildInfoRow(
                        'Public Port',
                        '${_diagnostics!.natInfo!.publicPort}',
                      ),
                      _buildInfoRow(
                        'NAT Type',
                        _natTypeLabel(_diagnostics!.natInfo!.natType),
                      ),
                    ],
                  ] else
                    const Text(
                      'Пока нет диагностики. Обновите экран, чтобы оценить NAT и relay-требования.',
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
                  const Text(
                    'Signaling / Relay Settings',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow('Signaling', settings.signalingServerUrl),
                  _buildInfoRow(
                    'Embedded Signaling',
                    appService.signalingUrl ?? 'Not running',
                  ),
                  _buildInfoRow(
                    'Advertised URL',
                    appService.advertisedSignalingUrl ?? 'Unknown',
                  ),
                  _buildInfoRow(
                    'Prefer Relay',
                    settings.preferRelay ? 'Yes' : 'No',
                  ),
                  _buildInfoRow(
                    'Legacy Direct',
                    settings.enableLegacyDirect ? 'Enabled' : 'Disabled',
                  ),
                  _buildInfoRow(
                    'Hosted Session',
                    mesh?.hostedSession?.sessionId ?? 'Not created',
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
                  const Text(
                    'Current Transport Plan',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow('Mode', transportPlan.summary),
                  _buildInfoRow('Details', transportPlan.details),
                  _buildInfoRow('Stage', appService.wanConnectionStage),
                  _buildInfoRow(
                    'Stage Details',
                    appService.wanConnectionDetails,
                  ),
                  _buildInfoRow(
                    'Signaling State',
                    appService.wanSignalingState,
                  ),
                  _buildInfoRow('ICE State', appService.wanIceState),
                  _buildInfoRow(
                    'DataChannel State',
                    appService.wanDataChannelState,
                  ),
                  if (appService.wanLastError != null)
                    _buildInfoRow('Last Error', appService.wanLastError!),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_inviteCode != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Invite Token',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      _inviteCode!.toShortCode(),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      _inviteCode!.toUrl(),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: _inviteCode!.toShortCode()),
                            );
                            _showSnack('Invite code скопирован');
                          },
                          icon: const Icon(Icons.copy),
                          label: const Text('Copy Code'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: _inviteCode!.toUrl()),
                            );
                            _showSnack('Invite URL скопирован');
                          },
                          icon: const Icon(Icons.link),
                          label: const Text('Copy URL'),
                        ),
                        FilledButton.icon(
                          onPressed: _showQrDialog,
                          icon: const Icon(Icons.qr_code),
                          label: const Text('QR'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Invite пока не создан. Проверьте доступность signaling server и нажмите refresh.',
                  style: TextStyle(color: Theme.of(context).colorScheme.outline),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.2),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Что важно',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 8),
                  Text('1. Для internet P2P invite token через signaling предпочтительнее ручного IP.'),
                  Text('2. TURN relay считается штатным fallback, а не ошибкой.'),
                  Text('3. Проброс портов на роутере теперь только опциональная оптимизация.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectTab(AppService appService, NetworkSettings settings) {
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
                  const Text(
                    'Connect With Invite',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _inputController,
                    decoration: const InputDecoration(
                      labelText: 'Invite token / URL / legacy IP:port',
                      hintText: 'scn://session/... or 203.0.113.10:53318',
                      prefixIcon: Icon(Icons.vpn_key),
                    ),
                    onSubmitted: (_) => _connect(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Password (optional)',
                      prefixIcon: Icon(Icons.lock),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _isConnecting ? null : _connect,
                    icon: _isConnecting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.link),
                    label: Text(_isConnecting ? 'Connecting...' : 'Connect'),
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
                  const Text(
                    'Current Mode',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow('Signaling', settings.signalingServerUrl),
                  _buildInfoRow(
                    'Embedded Signaling',
                    appService.signalingUrl ?? 'Not running',
                  ),
                  _buildInfoRow(
                    'Prefer Relay',
                    settings.preferRelay ? 'Yes' : 'No',
                  ),
                  _buildInfoRow(
                    'Legacy Direct Compatibility',
                    settings.enableLegacyDirect ? 'Enabled' : 'Disabled',
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
                  const Text(
                    'Live Status',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow('Stage', appService.wanConnectionStage),
                  _buildInfoRow('Details', appService.wanConnectionDetails),
                  _buildInfoRow('Signaling', appService.wanSignalingState),
                  _buildInfoRow('ICE', appService.wanIceState),
                  _buildInfoRow('DataChannel', appService.wanDataChannelState),
                  if (appService.wanLastError != null)
                    _buildInfoRow('Error', appService.wanLastError!),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.25),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Connection Notes',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 12),
                  Text('• Invite token через signaling нужен для нормального обмена SDP/ICE.'),
                  Text('• Direct path может не подняться за CGNAT или symmetric NAT. Это ожидаемо.'),
                  Text('• TURN relay должен покрывать такие случаи без ручного проброса порта.'),
                  Text('• Raw IP:port оставлен только как legacy fallback и не считается надежным WAN-путем.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeersTab(AppService appService, List<RemotePeer> peers) {
    final header = Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Current WAN Session',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _buildInfoRow('Stage', appService.wanConnectionStage),
            _buildInfoRow('Details', appService.wanConnectionDetails),
            _buildInfoRow('Signaling', appService.wanSignalingState),
            _buildInfoRow('ICE', appService.wanIceState),
            _buildInfoRow('DataChannel', appService.wanDataChannelState),
          ],
        ),
      ),
    );

    if (peers.isEmpty) {
      return Column(
        children: [
          header,
          Expanded(
            child: Center(
              child: Text(
                'Нет активных peers',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        header,
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: peers.length,
            itemBuilder: (context, index) {
              final peer = peers[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _statusColor(peer.status),
                    child: Icon(
                      peer.type == PeerType.local ? Icons.wifi : Icons.language,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(peer.alias),
                  subtitle: Text(
                    '${peer.address}:${peer.port}\n'
                    'transport=${peer.transport.name}, path=${peer.connectionPath.name}',
                  ),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'info') {
                        _showPeerDialog(peer);
                      } else if (value == 'disconnect') {
                        context.read<AppService>().meshService?.disconnectPeer(peer.id);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'info', child: Text('Details')),
                      PopupMenuItem(value: 'disconnect', child: Text('Disconnect')),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showPeerDialog(RemotePeer peer) {
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
            _buildInfoRow('Transport', peer.transport.name),
            _buildInfoRow('Path', peer.connectionPath.name),
            _buildInfoRow('Relay', peer.relayRequired ? 'Yes' : 'No'),
            if (peer.sessionId != null) _buildInfoRow('Session', peer.sessionId!),
            if (peer.signalingServerUrl != null)
              _buildInfoRow('Signaling', peer.signalingServerUrl!),
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
    if (_inviteCode == null) {
      _showSnack('Нет invite кода', isError: true);
      return;
    }

    final qrData = _inviteCode!.toUrl();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invite QR'),
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
              SelectableText(
                qrData,
                style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Отсканируйте QR или используйте invite URL',
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
              _showSnack('Invite URL скопирован');
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
            width: 120,
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

  String _natTypeLabel(NatType type) {
    switch (type) {
      case NatType.openInternet:
        return 'Open Internet';
      case NatType.fullCone:
        return 'Full Cone';
      case NatType.restrictedCone:
        return 'Restricted Cone';
      case NatType.portRestricted:
        return 'Port Restricted';
      case NatType.symmetric:
        return 'Symmetric / CGNAT';
      case NatType.unknown:
        return 'Unknown';
    }
  }

  IconData _reachabilityIcon(NetworkReachability reachability) {
    switch (reachability) {
      case NetworkReachability.directPossible:
        return Icons.check_circle_outline;
      case NetworkReachability.relayRecommended:
        return Icons.swap_horiz;
      case NetworkReachability.relayRequired:
        return Icons.hub_outlined;
      case NetworkReachability.unreachable:
        return Icons.error_outline;
      case NetworkReachability.unknown:
        return Icons.help_outline;
    }
  }

  Color _reachabilityColor(NetworkReachability reachability) {
    switch (reachability) {
      case NetworkReachability.directPossible:
        return Colors.green;
      case NetworkReachability.relayRecommended:
        return Colors.orange;
      case NetworkReachability.relayRequired:
        return Colors.deepOrange;
      case NetworkReachability.unreachable:
        return Colors.red;
      case NetworkReachability.unknown:
        return Colors.grey;
    }
  }

  Color _statusColor(PeerStatus status) {
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
