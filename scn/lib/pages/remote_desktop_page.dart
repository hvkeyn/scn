import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import 'package:scn/services/remote_desktop/remote_desktop_relay_service.dart';
import 'package:scn/utils/logger.dart';

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
  List<String> _localIps = const [];
  final Map<String, String> _savedLanPasswords = <String, String>{};

  @override
  void initState() {
    super.initState();
    _refreshLocalIps();
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshLocalIps() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      final ips = <String>[];
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            ips.add(addr.address);
          }
        }
      }
      ips.sort();
      if (!mounted) return;
      setState(() => _localIps = ips);
    } catch (e) {
      AppLogger.log('RD page: failed to enumerate local IPs: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final rdHost = context.watch<RemoteDesktopHostService>();
    final settings = context.watch<RemotePeerProvider>().settings.remoteDesktop;
    final app = context.watch<AppService>();

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
            _myAccessCard(context, app, settings),
            const SizedBox(height: 16),
            _wanAccessCard(context),
            const SizedBox(height: 16),
            _hostStatusCard(context, settings),
            const SizedBox(height: 16),
            _outgoingSessionCard(context),
            const SizedBox(height: 16),
            _connectCard(context),
            const SizedBox(height: 16),
            _discoveredPeersCard(context),
            const SizedBox(height: 16),
            _activeSessionsCard(context, rdHost),
          ],
        ),
      ),
    );
  }

  Widget _myAccessCard(
      BuildContext context, AppService app, RemoteDesktopSettings rd) {
    final scheme = Theme.of(context).colorScheme;
    final code = _connectionCodeForId(app.deviceId);
    final firstAddress = _localIps.isNotEmpty ? _localIps.first : null;
    final addressText =
        firstAddress == null ? null : '$firstAddress:${app.port}';

    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.important_devices,
                    color: scheme.onSecondaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Ваш рабочий стол',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: scheme.onSecondaryContainer,
                        ),
                  ),
                ),
                if (!rd.enabled)
                  FilledButton.icon(
                    icon: const Icon(Icons.power_settings_new),
                    label: const Text('Включить'),
                    onPressed: () => context
                        .read<RemotePeerProvider>()
                        .setRemoteDesktopEnabled(true),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _copyBlock(
                  context: context,
                  label: 'ID для подключения',
                  value: _formatConnectionCode(code),
                  copyValue: code,
                  icon: Icons.badge_outlined,
                ),
                if (addressText != null)
                  _copyBlock(
                    context: context,
                    label: 'IP:порт',
                    value: addressText,
                    copyValue: addressText,
                    icon: Icons.lan_outlined,
                  ),
                if (rd.password != null && rd.password!.isNotEmpty)
                  _copyBlock(
                    context: context,
                    label: 'Пароль для входа к вам',
                    value: rd.password!,
                    copyValue: rd.password!,
                    icon: Icons.password,
                  ),
              ],
            ),
            if (_localIps.length > 1) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _localIps
                    .map((ip) => ActionChip(
                          avatar: const Icon(Icons.copy, size: 16),
                          label: Text('$ip:${app.port}'),
                          onPressed: () => _copyText(
                              context, '$ip:${app.port}', 'IP:порт скопирован'),
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              rd.enabled
                  ? 'На другой машине можно ввести ID, выбрать устройство из LAN-списка или указать IP:порт вручную.'
                  : 'Включите hosting, чтобы этот рабочий стол принимал подключения.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSecondaryContainer.withOpacity(0.75),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _copyBlock({
    required BuildContext context,
    required String label,
    required String value,
    required String copyValue,
    required IconData icon,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surface.withOpacity(0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                SelectableText(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () => _copyText(context, copyValue, '$label скопирован'),
          ),
        ],
      ),
    );
  }

  Widget _wanAccessCard(BuildContext context) {
    final relay = context.watch<RemoteDesktopRelayService>();
    final scheme = Theme.of(context).colorScheme;
    final statusText = switch (relay.status) {
      RemoteDesktopRelayStatus.disabled => 'Отключён',
      RemoteDesktopRelayStatus.connecting => 'Подключение к relay...',
      RemoteDesktopRelayStatus.online => 'Онлайн через VPS',
      RemoteDesktopRelayStatus.offline => 'Нет соединения с relay',
      RemoteDesktopRelayStatus.error => 'Ошибка relay',
    };
    final code = relay.connectionCode;
    return Card(
      color: relay.isOnline ? scheme.tertiaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.public,
                    color: relay.isOnline ? scheme.onTertiaryContainer : null),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('WAN-доступ через сервер',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                Chip(label: Text(statusText)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _copyBlock(
                  context: context,
                  label: 'WAN ID',
                  value: _formatConnectionCode(code),
                  copyValue: code,
                  icon: Icons.cloud_queue,
                ),
                _copyBlock(
                  context: context,
                  label: 'Relay',
                  value: relay.relayUrl,
                  copyValue: relay.relayUrl,
                  icon: Icons.route,
                ),
              ],
            ),
            if (relay.lastError != null) ...[
              const SizedBox(height: 8),
              Text(relay.lastError!, style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: 8),
            Text(
              'Для подключения из интернета введите WAN ID в поле подключения. '
              'SCN использует relay/TURN, входящие порты на домашнем роутере не нужны.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
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
                Text('Hosting', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Switch.adaptive(
                  value: rd.enabled,
                  onChanged: (v) => context
                      .read<RemotePeerProvider>()
                      .setRemoteDesktopEnabled(v),
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
                style: TextStyle(color: Theme.of(context).colorScheme.outline)),
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
                      labelText: 'WAN/LAN ID, IP, host или IP:порт',
                      helperText:
                          'Экран: WAN ID или IP. Файлы: только LAN IP:порт.',
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
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.outline))
            else
              ...devices.map((d) => _peerListTile(context, d)),
          ],
        ),
      ),
    );
  }

  Widget _peerListTile(BuildContext context, Device device) {
    final code = _formatConnectionCode(_connectionCodeForId(device.id));
    return ListTile(
      leading: const Icon(Icons.computer),
      title: Text(device.alias),
      subtitle: Text('ID $code • ${device.ip}:${device.port}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Copy ID/IP',
            icon: const Icon(Icons.copy),
            onPressed: () => _copyText(
                context,
                '${_connectionCodeForId(device.id)}\n${device.ip}:${device.port}',
                'ID/IP copied'),
          ),
          IconButton(
            tooltip: 'Open file manager',
            icon: const Icon(Icons.folder_open),
            onPressed: () async {
              _hostCtrl.text = device.ip;
              _portCtrl.text = device.port.toString();
              final ok = await _ensurePasswordForLanDevice(device);
              if (!ok) return;
              _onManualOpenFiles();
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('Connect'),
            onPressed: () async {
              _hostCtrl.text = device.ip;
              _portCtrl.text = device.port.toString();
              final ok = await _ensurePasswordForLanDevice(device);
              if (!ok) return;
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
        AppLogger.log(
            'RD page: _outgoingSessionCard outer build, client=${client != null}');
        if (client == null) return const SizedBox.shrink();
        return AnimatedBuilder(
          animation: client,
          builder: (context, _) {
            final s = client.session;
            AppLogger.log(
                'RD page: _outgoingSessionCard inner build, session=${s != null}, status=${s?.status.name}');
            if (s == null) return const SizedBox.shrink();
            final scheme = Theme.of(context).colorScheme;
            return Card(
              color: scheme.primaryContainer,
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(_iconForStatus(s.status), color: scheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Active outgoing session',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(color: scheme.onPrimaryContainer)),
                          const SizedBox(height: 4),
                          Text('${s.peerAddress} • ${s.status.name}',
                              style: TextStyle(
                                  color: scheme.onPrimaryContainer
                                      .withOpacity(0.7))),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.open_in_full),
                      label: const Text('Continue'),
                      onPressed: () {
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
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.outline))
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
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.outline)),
            ),
            Expanded(child: SelectableText(v)),
          ],
        ),
      );

  Future<bool> _ensurePasswordForLanDevice(Device device) async {
    if (_passwordCtrl.text.trim().isNotEmpty) return true;
    final saved = await _savedPasswordForDevice(device);
    if (saved != null && saved.isNotEmpty) {
      _passwordCtrl.text = saved;
      return true;
    }

    final ctrl = TextEditingController();
    var remember = true;
    final result = await showDialog<String?>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Пароль удалённого устройства'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${device.alias} • ${device.ip}:${device.port}'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Пароль удалённой машины',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (value) =>
                        Navigator.of(context).pop(value.trim()),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: remember,
                    onChanged: (value) =>
                        setDialogState(() => remember = value ?? true),
                    title: const Text('Запомнить пароль для этого устройства'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  Text(
                    'Это пароль той машины, к которой подключаемся. '
                    'Локальный пароль из блока "Ваш рабочий стол" нужен другим '
                    'устройствам для входа к вам.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Отмена'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(''),
                  child: const Text('Без пароля'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
                  child: const Text('Подключиться'),
                ),
              ],
            );
          },
        );
      },
    );
    ctrl.dispose();
    if (!mounted || result == null) return false;
    if (result.isNotEmpty) {
      _passwordCtrl.text = result;
      if (remember) {
        await _savePasswordForDevice(device, result);
      }
    }
    return true;
  }

  Future<String?> _savedPasswordForDevice(Device device) async {
    final cached = _savedLanPasswords[device.id];
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_passwordPrefKey(device));
    if (saved != null && saved.isNotEmpty) {
      _savedLanPasswords[device.id] = saved;
    }
    return saved;
  }

  Future<void> _savePasswordForDevice(Device device, String password) async {
    _savedLanPasswords[device.id] = password;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_passwordPrefKey(device), password);
  }

  String _passwordPrefKey(Device device) =>
      'rd_lan_password_${device.id}_${device.ip}_${device.port}';

  void _onManualConnect() {
    final input = _hostCtrl.text.trim();
    final normalizedCode = _digitsOnly(input);
    final looksLikeCode = RegExp(r'^[\d\s-]+$').hasMatch(input);
    if (looksLikeCode &&
        normalizedCode.length >= 6 &&
        !_hasLanDeviceForCode(normalizedCode)) {
      final app = context.read<AppService>();
      final relay = context.read<RemoteDesktopRelayService>();
      final params = RemoteDesktopConnectParams(
        host: 'WAN ${_formatConnectionCode(normalizedCode.padLeft(9, '0'))}',
        port: 0,
        myDeviceId: app.deviceId,
        myAlias: app.deviceAlias,
        password: _passwordCtrl.text.isEmpty ? null : _passwordCtrl.text,
        wantControl: _wantControl,
        wantAudio: _wantAudio,
        relayUrl: relay.relayUrl,
        relayTargetId: normalizedCode,
      );
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RemoteDesktopViewerPage(params: params),
      ));
      return;
    }

    final target = _resolveConnectTarget();
    if (target == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите ID, IP или host:port')),
      );
      return;
    }
    final app = context.read<AppService>();
    final params = RemoteDesktopConnectParams(
      host: target.host,
      port: target.port,
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

  bool _hasLanDeviceForCode(String normalizedCode) {
    final devices = context.read<DeviceProvider>().devices;
    for (final device in devices) {
      final deviceCode = _connectionCodeForId(device.id);
      if (deviceCode == normalizedCode || deviceCode.endsWith(normalizedCode)) {
        return true;
      }
    }
    return false;
  }

  void _onManualOpenFiles() {
    final input = _hostCtrl.text.trim();
    if (_isWanOnlyCode(input)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Файлы через WAN ID пока не поддержаны. Для файлов укажите LAN IP:порт удалённого хоста.',
          ),
        ),
      );
      return;
    }

    final target = _resolveConnectTarget();
    if (target == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите ID, IP или host:port')),
      );
      return;
    }
    final app = context.read<AppService>();
    final params = RemoteFileSessionParams(
      host: target.host,
      port: target.port,
      viewerDeviceId: app.deviceId,
      viewerAlias: app.deviceAlias,
      password: _passwordCtrl.text.isEmpty ? null : _passwordCtrl.text,
    );
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RemoteFileManagerPage(
        params: params,
        title: 'Files: ${target.host}',
      ),
    ));
  }

  bool _isWanOnlyCode(String input) {
    final normalizedCode = _digitsOnly(input);
    return RegExp(r'^[\d\s-]+$').hasMatch(input) &&
        normalizedCode.length >= 6 &&
        !_hasLanDeviceForCode(normalizedCode);
  }

  _ConnectTarget? _resolveConnectTarget() {
    final input = _hostCtrl.text.trim();
    final portFromField = int.tryParse(_portCtrl.text.trim());
    if (input.isEmpty) return null;

    final normalizedCode = _digitsOnly(input);
    final devices = context.read<DeviceProvider>().devices;
    if (normalizedCode.length >= 6) {
      for (final device in devices) {
        final deviceCode = _connectionCodeForId(device.id);
        if (deviceCode == normalizedCode ||
            deviceCode.endsWith(normalizedCode)) {
          _hostCtrl.text = device.ip;
          _portCtrl.text = device.port.toString();
          return _ConnectTarget(device.ip, device.port);
        }
      }
    }

    final parsed = _parseHostPort(input, portFromField);
    if (parsed != null) {
      _hostCtrl.text = parsed.host;
      _portCtrl.text = parsed.port.toString();
      return parsed;
    }

    final lower = input.toLowerCase();
    for (final device in devices) {
      if (device.alias.toLowerCase() == lower || device.id == input) {
        _hostCtrl.text = device.ip;
        _portCtrl.text = device.port.toString();
        return _ConnectTarget(device.ip, device.port);
      }
    }

    final fallbackPort = portFromField ?? 53317;
    return _ConnectTarget(input, fallbackPort);
  }

  _ConnectTarget? _parseHostPort(String input, int? fallbackPort) {
    final uri = Uri.tryParse(input.contains('://') ? input : 'scn://$input');
    if (uri != null && uri.host.isNotEmpty) {
      return _ConnectTarget(
          uri.host, uri.hasPort ? uri.port : (fallbackPort ?? 53317));
    }
    final colon = input.lastIndexOf(':');
    if (colon > 0 && colon < input.length - 1) {
      final host = input.substring(0, colon).trim();
      final port = int.tryParse(input.substring(colon + 1).trim());
      if (host.isNotEmpty && port != null) {
        return _ConnectTarget(host, port);
      }
    }
    return null;
  }

  String _digitsOnly(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

  String _connectionCodeForId(String id) {
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return (hash % 1000000000).toString().padLeft(9, '0');
  }

  String _formatConnectionCode(String code) {
    final digits = _digitsOnly(code).padLeft(9, '0');
    return '${digits.substring(0, 3)} ${digits.substring(3, 6)} ${digits.substring(6, 9)}';
  }

  Future<void> _copyText(
      BuildContext context, String value, String message) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _ConnectTarget {
  final String host;
  final int port;

  const _ConnectTarget(this.host, this.port);
}
