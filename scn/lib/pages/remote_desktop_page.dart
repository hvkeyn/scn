import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:scn/models/device.dart';
import 'package:scn/models/remote_desktop_models.dart';
import 'package:scn/models/remote_file_models.dart';
import 'package:scn/pages/remote_desktop_viewer_page.dart';
import 'package:scn/pages/remote_file_manager_page.dart';
import 'package:scn/providers/device_provider.dart';
import 'package:scn/providers/remote_peer_provider.dart';
import 'package:scn/services/app_service.dart';
import 'package:scn/services/remote_desktop/remote_desktop_client_service.dart';
import 'package:scn/services/remote_desktop/remote_desktop_host_service.dart';

class RemoteDesktopPage extends StatefulWidget {
  const RemoteDesktopPage({super.key});

  @override
  State<RemoteDesktopPage> createState() => _RemoteDesktopPageState();
}

class _RemoteDesktopPageState extends State<RemoteDesktopPage> {
  final TextEditingController _hostCtrl = TextEditingController();
  final TextEditingController _portCtrl = TextEditingController(text: '53317');
  final TextEditingController _passwordCtrl = TextEditingController();
  bool _wantControl = true;
  bool _wantAudio = false;

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rdHost = context.watch<RemoteDesktopHostService>();
    final settings = context.watch<RemotePeerProvider>().settings.remoteDesktop;

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.desktop_windows, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Remote Desktop',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _hostStatusCard(context, settings),
            const SizedBox(height: 16),
            _connectCard(context),
            const SizedBox(height: 16),
            _outgoingSessionCard(context),
            const SizedBox(height: 16),
            _discoveredPeersCard(context),
            const SizedBox(height: 16),
            _activeSessionsCard(context, rdHost),
          ],
        ),
      ),
    );
  }

  Widget _hostStatusCard(BuildContext context, RemoteDesktopSettings rd) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  rd.enabled ? Icons.cast_connected : Icons.cast,
                  color: rd.enabled
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 12),
                Text('Hosting',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Switch.adaptive(
                  value: rd.enabled,
                  onChanged: (v) =>
                      context.read<RemotePeerProvider>().setRemoteDesktopEnabled(v),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (!rd.enabled)
              Text(
                'Enable hosting to allow other devices to view this screen.',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              )
            else ...[
              _kv('Mode', _accessModeLabel(rd.accessMode)),
              if (rd.password != null) _passwordRow(context, rd.password!),
              _kv('Audio shared', rd.shareAudio ? 'Yes' : 'No'),
              _kv('View-only', rd.viewOnlyByDefault ? 'Yes' : 'No'),
              if (rd.preferredVideoCodec != 'auto')
                _kv('Codec', rd.preferredVideoCodec),
              const SizedBox(height: 8),
              Text(
                'Manage these in Settings → Remote Desktop.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _passwordRow(BuildContext context, String password) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text('Password:',
                style:
                    TextStyle(color: Theme.of(context).colorScheme.outline)),
          ),
          Expanded(
            child: SelectableText(
              password,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: password));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Password copied')),
              );
            },
          ),
          IconButton(
            tooltip: 'Regenerate',
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: () => context
                .read<RemotePeerProvider>()
                .regenerateRemoteDesktopPassword(),
          ),
        ],
      ),
    );
  }

  Widget _connectCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Connect to a host',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _hostCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Host (IP or DNS)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _portCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password (if required)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Switch.adaptive(
                  value: _wantControl,
                  onChanged: (v) => setState(() => _wantControl = v),
                ),
                const Text('Request control'),
                const SizedBox(width: 16),
                Switch.adaptive(
                  value: _wantAudio,
                  onChanged: (v) => setState(() => _wantAudio = v),
                ),
                const Text('Audio'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _onManualConnect,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('View screen'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _onManualOpenFiles,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Open files'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _discoveredPeersCard(BuildContext context) {
    final deviceProvider = context.watch<DeviceProvider>();
    final devices = deviceProvider.devices;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Discovered on LAN',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (devices.isEmpty)
              Text('No devices discovered yet.',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.outline))
            else
              ...devices.map((d) => _peerListTile(context, d)),
          ],
        ),
      ),
    );
  }

  Widget _peerListTile(BuildContext context, Device device) {
    return ListTile(
      leading: const Icon(Icons.computer),
      title: Text(device.alias),
      subtitle: Text('${device.ip}:${device.port}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Open file manager',
            icon: const Icon(Icons.folder_open),
            onPressed: () {
              _hostCtrl.text = device.ip;
              _portCtrl.text = device.port.toString();
              _onManualOpenFiles();
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('Connect'),
            onPressed: () {
              _hostCtrl.text = device.ip;
              _portCtrl.text = device.port.toString();
              _onManualConnect();
            },
          ),
        ],
      ),
    );
  }

  /// Карточка активной исходящей сессии (мы как viewer): если клиент-сервис
  /// не nullable, показываем её и даём кнопки Continue / Disconnect. Это
  /// нужно чтобы юзер мог вернуться в сессию после нажатия back.
  Widget _outgoingSessionCard(BuildContext context) {
    return AnimatedBuilder(
      animation: RemoteDesktopClientService.activeListenable,
      builder: (context, _) {
        final client = RemoteDesktopClientService.active;
        final session = client?.session;
        if (client == null || session == null) {
          return const SizedBox.shrink();
        }
        // Подписываемся ещё и на сам клиент, чтобы реагировать на смену
        // status (negotiating → streaming → closed).
        return AnimatedBuilder(
          animation: client,
          builder: (context, _) {
            final s = client.session;
            if (s == null) return const SizedBox.shrink();
            return Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(_iconForStatus(s.status),
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Active outgoing session',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text('${s.peerAddress} • ${s.status.name}',
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outline)),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.open_in_full),
                      label: const Text('Continue'),
                      onPressed: () {
                        // Возвращаемся на viewer-page. Page подхватит активный
                        // клиент и не будет переподключаться.
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => RemoteDesktopViewerPage(
                            params: client.lastParams ??
                                RemoteDesktopConnectParams(
                                  host: s.peerAddress,
                                  port: s.peerPort,
                                  myDeviceId: '',
                                  myAlias: '',
                                ),
                          ),
                        ));
                      },
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.close),
                      label: const Text('Disconnect'),
                      onPressed: () async {
                        await client.disconnect();
                        client.dispose();
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _activeSessionsCard(
      BuildContext context, RemoteDesktopHostService host) {
    final sessions = host.sessions;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Incoming sessions',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (sessions.isEmpty)
              Text('No active sessions.',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.outline))
            else
              ...sessions.map((s) => ListTile(
                    leading: Icon(_iconForStatus(s.status)),
                    title: Text(s.peerAlias),
                    subtitle: Text(
                      '${s.peerAddress} • ${s.status.name}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Disconnect viewer',
                      onPressed: () => host.kickSession(s.sessionId),
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  IconData _iconForStatus(RemoteDesktopSessionStatus status) {
    switch (status) {
      case RemoteDesktopSessionStatus.streaming:
        return Icons.cast_connected;
      case RemoteDesktopSessionStatus.negotiating:
      case RemoteDesktopSessionStatus.pendingApproval:
        return Icons.hourglass_top;
      case RemoteDesktopSessionStatus.failed:
      case RemoteDesktopSessionStatus.rejected:
        return Icons.error_outline;
      case RemoteDesktopSessionStatus.closed:
        return Icons.cancel_outlined;
    }
  }

  String _accessModeLabel(RemoteDesktopAccessMode mode) {
    switch (mode) {
      case RemoteDesktopAccessMode.disabled:
        return 'Disabled';
      case RemoteDesktopAccessMode.passwordOnly:
        return 'Password only';
      case RemoteDesktopAccessMode.promptOnly:
        return 'Prompt only';
      case RemoteDesktopAccessMode.passwordOrPrompt:
        return 'Password or prompt';
    }
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            SizedBox(
              width: 110,
              child: Text('$k:',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.outline)),
            ),
            Expanded(child: SelectableText(v)),
          ],
        ),
      );

  void _onManualConnect() {
    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim());
    if (host.isEmpty || port == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Provide host and port')),
      );
      return;
    }
    final app = context.read<AppService>();
    final params = RemoteDesktopConnectParams(
      host: host,
      port: port,
      myDeviceId: app.deviceId,
      myAlias: app.deviceAlias,
      password: _passwordCtrl.text.isEmpty ? null : _passwordCtrl.text,
      wantControl: _wantControl,
      wantAudio: _wantAudio,
    );
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RemoteDesktopViewerPage(params: params),
    ));
  }

  void _onManualOpenFiles() {
    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim());
    if (host.isEmpty || port == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Provide host and port')),
      );
      return;
    }
    final app = context.read<AppService>();
    final params = RemoteFileSessionParams(
      host: host,
      port: port,
      viewerDeviceId: app.deviceId,
      viewerAlias: app.deviceAlias,
      password: _passwordCtrl.text.isEmpty ? null : _passwordCtrl.text,
    );
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RemoteFileManagerPage(
        params: params,
        title: 'Files: $host',
      ),
    ));
  }
}
