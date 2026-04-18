import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:scn/services/app_service.dart';
import 'package:scn/providers/remote_peer_provider.dart';
import 'package:scn/providers/chat_provider.dart';
import 'package:scn/providers/receive_provider.dart';
import 'package:scn/providers/send_provider.dart';
import 'package:scn/models/remote_peer.dart';
import 'package:scn/models/remote_desktop_models.dart';
import 'package:scn/services/desktop_integration_service.dart';
import 'package:scn/services/update_service.dart';
import 'package:scn/widgets/scn_logo.dart';
import 'package:scn/utils/test_config.dart';
import 'package:scn/pages/vpn_page.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final UpdateService _updateService = UpdateService();
  String _currentVersion = '...';
  String _currentVersionName = '0.0.0';
  int _currentBuild = 0;
  UpdateInfo? _latestUpdate;
  List<String> _latestChanges = const [];
  String? _updateError;
  bool _checkingUpdate = false;
  bool _installingUpdate = false;
  DateTime? _lastChecked;

  @override
  void initState() {
    super.initState();
    _loadCurrentVersion();
    _fetchUpdateStatus();
  }

  Future<void> _loadCurrentVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _currentVersionName = info.version;
      _currentBuild = int.tryParse(info.buildNumber) ?? 0;
      _currentVersion = '${info.version}+${info.buildNumber}';
    });
  }

  Future<void> _fetchUpdateStatus({bool showSnack = false}) async {
    if (_checkingUpdate || _installingUpdate) return;
    if (TestConfig.current.isTestMode) return;
    setState(() {
      _checkingUpdate = true;
      _updateError = null;
    });
    UpdateInfo? latest;
    try {
      latest = await _updateService.fetchLatest();
    } catch (_) {
      latest = null;
    }
    if (!mounted) return;
    if (latest == null) {
      setState(() {
        _latestUpdate = null;
        _latestChanges = const [];
        _updateError = 'Нет связи с сервером обновлений';
        _lastChecked = DateTime.now();
        _checkingUpdate = false;
      });
      if (showSnack) {
        _showSnack('Нет связи с сервером обновлений', isError: true);
      }
      return;
    }

    final updateAvailable = _isUpdateAvailable(latest);
    final List<String> changes =
        updateAvailable ? await _updateService.loadChanges(latest) : const [];
    if (!mounted) return;
    setState(() {
      _latestUpdate = latest;
      _latestChanges = changes;
      _updateError = null;
      _lastChecked = DateTime.now();
      _checkingUpdate = false;
    });
    if (showSnack) {
      _showSnack(
        updateAvailable
            ? 'Доступно обновление ${latest.displayVersion}'
            : 'У вас последняя версия',
      );
    }
  }

  Future<void> _installUpdate(UpdateInfo info) async {
    if (_installingUpdate) return;
    setState(() => _installingUpdate = true);
    _showSnack('Скачивание обновления...');
    try {
      await _updateService.downloadAndInstall(info);
    } catch (e) {
      if (!mounted) return;
      setState(() => _installingUpdate = false);
      _showSnack('Ошибка обновления: $e', isError: true);
    }
  }

  bool _isUpdateAvailable(UpdateInfo info) {
    if (_currentBuild != 0 && info.build != 0) {
      if (info.build > _currentBuild) return true;
      if (info.build < _currentBuild) return false;
    }
    return _compareSemver(info.version, _currentVersionName) > 0;
  }

  int _compareSemver(String a, String b) {
    final pa = a.split('.');
    final pb = b.split('.');
    for (var i = 0; i < 3; i++) {
      final ai = i < pa.length ? int.tryParse(pa[i]) ?? 0 : 0;
      final bi = i < pb.length ? int.tryParse(pb[i]) ?? 0 : 0;
      if (ai != bi) return ai.compareTo(bi);
    }
    return 0;
  }

  String _formatDateTime(DateTime value) {
    final text = value.toString().replaceFirst('T', ' ');
    return text.length > 19 ? text.substring(0, 19) : text;
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
    final appService = context.watch<AppService>();
    final peerProvider = context.watch<RemotePeerProvider>();
    final desktopService = context.watch<DesktopIntegrationService>();
    final settings = peerProvider.settings;
    final theme = Theme.of(context);
    final updateAvailable = _latestUpdate != null && _isUpdateAvailable(_latestUpdate!);
    final serverVersion = _latestUpdate?.displayVersion ??
        (_updateError != null ? 'нет связи' : 'неизвестно');
    final statusText = _updateError != null
        ? 'нет связи'
        : (_latestUpdate == null
            ? 'неизвестно'
            : (updateAvailable ? 'доступно обновление' : 'последняя версия'));
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // About Section
        _buildCard(
          context,
          child: ListTile(
            leading: const SCNLogo(size: 40),
            title: const Text('About', style: TextStyle(color: Colors.white)),
            subtitle: Text('SCN $_currentVersion', style: TextStyle(color: Colors.white.withOpacity(0.5))),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationIcon: const SCNLogo(size: 64),
                applicationName: 'SCN',
                applicationVersion: _currentVersion,
                applicationLegalese: '© 2025 SCN Team',
              );
            },
          ),
        ),
        
        const SizedBox(height: 16),
        _buildSectionTitle(context, 'Updates'),
        _buildCard(
          context,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.system_update, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Обновления', style: TextStyle(color: Colors.white)),
                          Text(
                            TestConfig.current.isTestMode
                                ? 'Отключено в тестовом режиме'
                                : 'Автопроверка включена',
                            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildInfoRow('Текущая версия', _currentVersion),
                const SizedBox(height: 6),
                _buildInfoRow('Версия на сервере', serverVersion),
                const SizedBox(height: 6),
                _buildInfoRow('Статус', statusText),
                if (_lastChecked != null) ...[
                  const SizedBox(height: 6),
                  _buildInfoRow('Последняя проверка', _formatDateTime(_lastChecked!)),
                ],
                if (updateAvailable && _latestChanges.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Список изменений:', style: TextStyle(color: Colors.white.withOpacity(0.8))),
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 160),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _latestChanges.map((e) => Text('• $e')).toList(),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      icon: _checkingUpdate
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: const Text('Проверить'),
                      onPressed: (_checkingUpdate || _installingUpdate || TestConfig.current.isTestMode)
                          ? null
                          : () => _fetchUpdateStatus(showSnack: true),
                    ),
                    const Spacer(),
                    if (updateAvailable)
                      FilledButton.icon(
                        icon: _installingUpdate
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.download),
                        label: const Text('Обновить'),
                        onPressed: (_installingUpdate || TestConfig.current.isTestMode)
                            ? null
                            : () => _installUpdate(_latestUpdate!),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        _buildSectionTitle(context, 'Server'),
        
        // Server Status
        _buildCard(
          context,
          child: Column(
            children: [
              SwitchListTile(
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: appService.running 
                        ? Colors.green.withOpacity(0.2) 
                        : Colors.grey.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.dns,
                    color: appService.running ? Colors.green : Colors.grey,
                  ),
                ),
                title: const Text('Server Status', style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  appService.running ? 'Running on port ${appService.port}' : 'Stopped',
                  style: TextStyle(color: Colors.white.withOpacity(0.5)),
                ),
                value: appService.running,
                activeColor: theme.colorScheme.primary,
                onChanged: (value) async {
                  if (value) {
                    await appService.initialize();
                  } else {
                    await appService.stop();
                  }
                },
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        _buildSectionTitle(context, 'Device'),
        
        // Device Name
        _buildCard(
          context,
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.badge, color: theme.colorScheme.primary),
            ),
            title: const Text('Device Name', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              appService.deviceAlias,
              style: TextStyle(color: Colors.white.withOpacity(0.5)),
            ),
            trailing: Icon(Icons.edit, color: Colors.white.withOpacity(0.5)),
            onTap: () => _showDeviceNameDialog(context, appService),
          ),
        ),
        
        const SizedBox(height: 8),
        
        // Download Directory
        _buildCard(
          context,
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.folder, color: Colors.orange),
            ),
            title: const Text('Download Directory', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              'Downloads',
              style: TextStyle(color: Colors.white.withOpacity(0.5)),
            ),
            trailing: Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.5)),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Directory picker not yet implemented')),
              );
            },
          ),
        ),
        
        const SizedBox(height: 16),
        _buildSectionTitle(context, 'Mesh Network'),
        
        // Mesh Network Toggle
        _buildCard(
          context,
          child: Column(
            children: [
              SwitchListTile(
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: settings.meshEnabled 
                        ? Colors.purple.withOpacity(0.2) 
                        : Colors.grey.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.hub,
                    color: settings.meshEnabled ? Colors.purple : Colors.grey,
                  ),
                ),
                title: const Text('Mesh Network', style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  settings.meshEnabled 
                      ? 'Discover peers through other connected devices'
                      : 'Only direct connections',
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                ),
                value: settings.meshEnabled,
                activeColor: theme.colorScheme.primary,
                onChanged: (value) => peerProvider.setMeshEnabled(value),
              ),
              if (settings.meshEnabled) ...[
                Divider(color: Colors.white.withOpacity(0.1)),
                SwitchListTile(
                  secondary: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.share, color: Colors.white.withOpacity(0.5), size: 20),
                  ),
                  title: Text(
                    'Share my peers',
                    style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
                  ),
                  subtitle: Text(
                    'Allow others to see devices connected to me',
                    style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                  ),
                  value: settings.sharePeers,
                  activeColor: theme.colorScheme.primary,
                  onChanged: (value) => peerProvider.setSharePeers(value),
                ),
              ],
            ],
          ),
        ),
        
        // VPN / Internet P2P Button
        const SizedBox(height: 8),
        _buildCard(
          context,
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.vpn_key, color: Colors.blue),
            ),
            title: const Text('Internet P2P / Relay', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              'Invite-based WAN connections via signaling + WebRTC',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
            ),
            trailing: Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.5)),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const VpnPage()),
              );
            },
          ),
        ),

        const SizedBox(height: 8),
        _buildCard(
          context,
          child: Column(
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.router, color: Colors.teal),
                ),
                title: const Text('Signaling Server', style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  settings.signalingServerUrl,
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                ),
                trailing: Icon(Icons.edit, color: Colors.white.withOpacity(0.5)),
                onTap: () => _showSignalingServerDialog(context, peerProvider),
              ),
              Divider(color: Colors.white.withOpacity(0.1)),
              SwitchListTile(
                secondary: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.compare_arrows, color: Colors.white.withOpacity(0.5), size: 20),
                ),
                title: Text(
                  'Prefer relay when needed',
                  style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
                ),
                subtitle: Text(
                  'Force TURN-friendly path instead of overpromising direct reachability',
                  style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                ),
                value: settings.preferRelay,
                activeColor: theme.colorScheme.primary,
                onChanged: (value) => peerProvider.setPreferRelay(value),
              ),
              Divider(color: Colors.white.withOpacity(0.1)),
              SwitchListTile(
                secondary: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.cable, color: Colors.white.withOpacity(0.5), size: 20),
                ),
                title: Text(
                  'Allow legacy direct IP mode',
                  style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
                ),
                subtitle: Text(
                  'Compatibility only. Not considered reliable WAN connectivity.',
                  style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                ),
                value: settings.enableLegacyDirect,
                activeColor: theme.colorScheme.primary,
                onChanged: (value) => peerProvider.setEnableLegacyDirect(value),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        _buildSectionTitle(context, 'Security'),
        
        // Password Protection
        _buildCard(
          context,
          child: Column(
            children: [
              SwitchListTile(
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: !settings.acceptWithoutPassword 
                        ? Colors.red.withOpacity(0.2) 
                        : Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    !settings.acceptWithoutPassword ? Icons.lock : Icons.lock_open,
                    color: !settings.acceptWithoutPassword ? Colors.red : Colors.green,
                  ),
                ),
                title: const Text('Require Password', style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  !settings.acceptWithoutPassword 
                      ? 'Others need password to connect'
                      : 'Anyone can connect without password',
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                ),
                value: !settings.acceptWithoutPassword,
                activeColor: theme.colorScheme.primary,
                onChanged: (value) => peerProvider.setAcceptWithoutPassword(!value),
              ),
              if (!settings.acceptWithoutPassword) ...[
                Divider(color: Colors.white.withOpacity(0.1)),
                ListTile(
                  leading: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.key, color: Colors.white.withOpacity(0.5), size: 20),
                  ),
                  title: Text(
                    'Connection Password',
                    style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
                  ),
                  subtitle: Text(
                    settings.connectionPassword?.isNotEmpty == true 
                        ? '••••••••' 
                        : 'Not set',
                    style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
                  ),
                  trailing: Icon(Icons.edit, color: Colors.white.withOpacity(0.5), size: 18),
                  onTap: () => _showPasswordDialog(context, peerProvider),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),
        _buildSectionTitle(context, 'Remote Desktop'),
        _buildRemoteDesktopCard(context, peerProvider, settings.remoteDesktop),

        const SizedBox(height: 16),
        _buildSectionTitle(context, 'Network Info'),
        
        // Network Port Info
        _buildCard(
          context,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('HTTP Server Port', '${appService.port}'),
                const SizedBox(height: 8),
                _buildInfoRow('Secure Channel Port', '${settings.securePort}'),
                const SizedBox(height: 8),
                _buildInfoRow('Multicast Port', '53317'),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.blue, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Keep outbound access available. Router port forwarding is now optional and mainly useful as an optimization for legacy direct mode.',
                          style: TextStyle(
                            color: Colors.blue.shade200,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        if (desktopService.available && desktopService.initialized) ...[
          _buildSectionTitle(context, 'System'),
          _buildCard(
            context,
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.minimize, color: Colors.blueGrey),
                  ),
                  title: const Text('Minimize to tray', style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    'Hide window when minimized',
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                  ),
                  value: desktopService.minimizeToTray,
                  activeColor: theme.colorScheme.primary,
                  onChanged: (value) => desktopService.setMinimizeToTray(value),
                ),
                const Divider(height: 1, color: Colors.white12),
                SwitchListTile(
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.indigo.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.close, color: Colors.indigo),
                  ),
                  title: const Text('Close to tray', style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    'Keep running when window is closed',
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                  ),
                  value: desktopService.closeToTray,
                  activeColor: theme.colorScheme.primary,
                  onChanged: (value) => desktopService.setCloseToTray(value),
                ),
                const Divider(height: 1, color: Colors.white12),
                SwitchListTile(
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.power_settings_new, color: Colors.green),
                  ),
                  title: const Text('Launch at startup', style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    'Start SCN with Windows',
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                  ),
                  value: desktopService.launchAtStartup,
                  activeColor: theme.colorScheme.primary,
                  onChanged: (value) => desktopService.setLaunchAtStartup(value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        
        _buildSectionTitle(context, 'History'),
        
        // History - Clear chat and file history
        _buildCard(
          context,
          child: Column(
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.history, color: Colors.blue),
                ),
                title: const Text('Chat History', style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  'Clear all messages',
                  style: TextStyle(color: Colors.white.withOpacity(0.5)),
                ),
                trailing: TextButton(
                  onPressed: () => _confirmClearChatHistory(context),
                  child: const Text('Clear', style: TextStyle(color: Colors.red)),
                ),
              ),
              const Divider(height: 1, color: Colors.white12),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.download, color: Colors.green),
                ),
                title: const Text('Received Files', style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  'Clear receive history',
                  style: TextStyle(color: Colors.white.withOpacity(0.5)),
                ),
                trailing: TextButton(
                  onPressed: () => _confirmClearReceiveHistory(context),
                  child: const Text('Clear', style: TextStyle(color: Colors.red)),
                ),
              ),
              const Divider(height: 1, color: Colors.white12),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.upload, color: Colors.orange),
                ),
                title: const Text('Sent Files', style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  'Clear send history',
                  style: TextStyle(color: Colors.white.withOpacity(0.5)),
                ),
                trailing: TextButton(
                  onPressed: () => _confirmClearSendHistory(context),
                  child: const Text('Clear', style: TextStyle(color: Colors.red)),
                ),
              ),
              const Divider(height: 1, color: Colors.white12),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.delete_forever, color: Colors.red),
                ),
                title: const Text('Clear All History', style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  'Delete everything',
                  style: TextStyle(color: Colors.white.withOpacity(0.5)),
                ),
                trailing: TextButton(
                  onPressed: () => _confirmClearAllHistory(context),
                  child: const Text('Clear All', style: TextStyle(color: Colors.red)),
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        _buildSectionTitle(context, 'Test Mode'),
        
        // Test Mode - Launch and manage test instances
        _buildCard(
          context,
          child: Column(
            children: [
              // Header with status
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: TestConfig.current.isTestMode 
                        ? Colors.orange.withOpacity(0.2)
                        : Colors.amber.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    TestConfig.current.isTestMode ? Icons.bug_report : Icons.science,
                    color: TestConfig.current.isTestMode ? Colors.orange : Colors.amber,
                  ),
                ),
                title: Text(
                  TestConfig.current.isTestMode 
                      ? 'TEST INSTANCE #${TestConfig.current.instanceNumber}'
                      : 'Local Testing',
                  style: TextStyle(
                    color: TestConfig.current.isTestMode ? Colors.orange : Colors.white,
                    fontWeight: TestConfig.current.isTestMode ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                subtitle: Text(
                  TestConfig.current.isTestMode 
                      ? 'Port: ${TestConfig.current.httpPort} • Separate storage'
                      : 'Launch test instances to simulate remote devices',
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                ),
              ),
              
              Divider(color: Colors.white.withOpacity(0.1)),
              
              // Main action: Launch or Exit
              if (TestConfig.current.isTestMode) ...[
                // Exit test mode button
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _exitTestMode(context),
                      icon: const Icon(Icons.exit_to_app),
                      label: const Text('Exit Test Mode'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
                // Info about this test instance
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.info_outline, color: Colors.orange, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Test Instance Info',
                              style: TextStyle(color: Colors.orange.shade200, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '• This is a separate instance with its own data\n'
                          '• Changes here won\'t affect main app\n'
                          '• HTTP Port: ${TestConfig.current.httpPort}\n'
                          '• Mesh Port: ${TestConfig.current.meshPort}',
                          style: TextStyle(color: Colors.orange.shade200, fontSize: 11, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                // Launch test instance button
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _launchTestInstance(context),
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Launch Test Instance'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
                // Quick connect to existing instances
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        'Connect to running instances:',
                        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [1, 2, 3, 4].map((instanceNum) {
                      final port = TestConfig.basePort + (instanceNum * 10);
                      return OutlinedButton.icon(
                        onPressed: () => _connectToLocalInstance(context, peerProvider, port, instanceNum),
                        icon: const Icon(Icons.link, size: 16),
                        label: Text('#$instanceNum'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.amber,
                          side: BorderSide(color: Colors.amber.withOpacity(0.3)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                // Info
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lightbulb_outline, color: Colors.amber, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Test instances simulate remote devices on localhost with separate data storage',
                            style: TextStyle(color: Colors.amber.shade200, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        
        const SizedBox(height: 32),
      ],
    );
  }
  
  void _launchTestInstance(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final instanceNum = await TestConfig.findNextAvailableInstance();
    if (!context.mounted) return;

    messenger.showSnackBar(
      SnackBar(
        content: Text('Launching Test Instance #$instanceNum...'),
        backgroundColor: Colors.amber.shade700,
      ),
    );
    
    final success = await TestConfig.launchTestInstance(instanceNum);
    
    if (context.mounted) {
      if (success) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Test Instance #$instanceNum launched! Port: ${TestConfig.basePort + (instanceNum * 10)}'),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Failed to launch test instance'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }
  
  void _exitTestMode(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Exit Test Mode?', style: TextStyle(color: Colors.white)),
        content: Text(
          'This will close Test Instance #${TestConfig.current.instanceNumber}.\n\n'
          'The main application and other instances will continue running.',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.7))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              TestConfig.exitTestInstance();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }
  
  void _connectToLocalInstance(BuildContext context, RemotePeerProvider peerProvider, int port, int instanceNum) {
    final peer = RemotePeer(
      id: 'local-test-$port',
      alias: 'Test Instance #$instanceNum',
      address: '127.0.0.1',
      port: port,
      type: PeerType.local,
      status: PeerStatus.connecting,
    );
    peerProvider.addPeer(peer);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Connecting to Test Instance #$instanceNum (port $port)...'),
        backgroundColor: Colors.amber.shade700,
      ),
    );
  }
  
  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Colors.white.withOpacity(0.5),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }
  
  Widget _buildCard(BuildContext context, {required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: child,
    );
  }

  Widget _buildRemoteDesktopCard(BuildContext context,
      RemotePeerProvider provider, RemoteDesktopSettings rd) {
    final theme = Theme.of(context);
    return _buildCard(
      context,
      child: Column(
        children: [
          SwitchListTile(
            secondary: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: rd.enabled
                    ? Colors.green.withOpacity(0.2)
                    : Colors.grey.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                rd.enabled
                    ? Icons.cast_connected
                    : Icons.cast,
                color: rd.enabled ? Colors.green : Colors.grey,
              ),
            ),
            title: const Text('Allow remote desktop',
                style: TextStyle(color: Colors.white)),
            subtitle: Text(
              rd.enabled
                  ? 'Other devices can request to view this screen'
                  : 'Hosting is disabled',
              style:
                  TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
            ),
            value: rd.enabled,
            activeColor: theme.colorScheme.primary,
            onChanged: (v) => provider.setRemoteDesktopEnabled(v),
          ),
          if (rd.enabled) ...[
            Divider(color: Colors.white.withOpacity(0.1)),
            ListTile(
              leading: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.shield,
                    color: Colors.white.withOpacity(0.6), size: 20),
              ),
              title: Text('Access mode',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.85), fontSize: 14)),
              subtitle: Text(_rdAccessLabel(rd.accessMode),
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.45), fontSize: 12)),
              trailing: PopupMenuButton<RemoteDesktopAccessMode>(
                icon: const Icon(Icons.expand_more, color: Colors.white70),
                onSelected: provider.setRemoteDesktopAccessMode,
                itemBuilder: (_) => RemoteDesktopAccessMode.values
                    .where((m) => m != RemoteDesktopAccessMode.disabled)
                    .map((m) => PopupMenuItem(
                          value: m,
                          child: Text(_rdAccessLabel(m)),
                        ))
                    .toList(),
              ),
            ),
            Divider(color: Colors.white.withOpacity(0.1)),
            ListTile(
              leading: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.password,
                    color: Colors.white.withOpacity(0.6), size: 20),
              ),
              title: Text('Permanent password',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.85), fontSize: 14)),
              subtitle: SelectableText(
                rd.password ?? 'Not generated yet',
                style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontSize: 13),
              ),
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    tooltip: 'Regenerate',
                    icon: const Icon(Icons.refresh,
                        size: 18, color: Colors.white70),
                    onPressed: () => provider
                        .regenerateRemoteDesktopPassword(),
                  ),
                  IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.clear,
                        size: 18, color: Colors.white70),
                    onPressed: () =>
                        provider.setRemoteDesktopPassword(null),
                  ),
                ],
              ),
            ),
            Divider(color: Colors.white.withOpacity(0.1)),
            SwitchListTile(
              secondary: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.visibility_outlined,
                    color: Colors.white.withOpacity(0.6), size: 20),
              ),
              title: const Text('View-only by default',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              subtitle: Text('Disallow remote control inputs',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.45), fontSize: 12)),
              value: rd.viewOnlyByDefault,
              activeColor: theme.colorScheme.primary,
              onChanged: provider.setRemoteDesktopViewOnly,
            ),
            Divider(color: Colors.white.withOpacity(0.1)),
            SwitchListTile(
              secondary: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.volume_up_outlined,
                    color: Colors.white.withOpacity(0.6), size: 20),
              ),
              title: const Text('Share system audio',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              subtitle: Text(
                  'When supported by OS (Windows/macOS WASAPI/CoreAudio)',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.45), fontSize: 12)),
              value: rd.shareAudio,
              activeColor: theme.colorScheme.primary,
              onChanged: provider.setRemoteDesktopShareAudio,
            ),
            Divider(color: Colors.white.withOpacity(0.1)),
            ListTile(
              leading: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.high_quality,
                    color: Colors.white.withOpacity(0.6), size: 20),
              ),
              title: Text('Default bitrate',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.85), fontSize: 14)),
              subtitle: Text(
                  rd.defaultVideoBitrateKbps == 0
                      ? 'Auto'
                      : '${rd.defaultVideoBitrateKbps} kbps',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.45), fontSize: 12)),
              trailing: PopupMenuButton<int>(
                icon: const Icon(Icons.expand_more, color: Colors.white70),
                onSelected: provider.setRemoteDesktopBitrate,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 0, child: Text('Auto')),
                  PopupMenuItem(value: 1500, child: Text('1.5 Mbps')),
                  PopupMenuItem(value: 3000, child: Text('3 Mbps')),
                  PopupMenuItem(value: 6000, child: Text('6 Mbps')),
                  PopupMenuItem(value: 12000, child: Text('12 Mbps')),
                  PopupMenuItem(value: 25000, child: Text('25 Mbps')),
                ],
              ),
            ),
            Divider(color: Colors.white.withOpacity(0.1)),
            ListTile(
              leading: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.speed,
                    color: Colors.white.withOpacity(0.6), size: 20),
              ),
              title: Text('Default FPS',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.85), fontSize: 14)),
              subtitle: Text(
                  rd.defaultFps == 0 ? 'Auto' : '${rd.defaultFps} fps',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.45), fontSize: 12)),
              trailing: PopupMenuButton<int>(
                icon: const Icon(Icons.expand_more, color: Colors.white70),
                onSelected: provider.setRemoteDesktopFps,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 0, child: Text('Auto')),
                  PopupMenuItem(value: 15, child: Text('15')),
                  PopupMenuItem(value: 24, child: Text('24')),
                  PopupMenuItem(value: 30, child: Text('30')),
                  PopupMenuItem(value: 60, child: Text('60')),
                ],
              ),
            ),
            Divider(color: Colors.white.withOpacity(0.1)),
            ListTile(
              leading: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.video_settings,
                    color: Colors.white.withOpacity(0.6), size: 20),
              ),
              title: Text('Preferred codec',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.85), fontSize: 14)),
              subtitle: Text(rd.preferredVideoCodec.toUpperCase(),
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.45), fontSize: 12)),
              trailing: PopupMenuButton<String>(
                icon: const Icon(Icons.expand_more, color: Colors.white70),
                onSelected: provider.setRemoteDesktopCodec,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'auto', child: Text('Auto')),
                  PopupMenuItem(value: 'H264', child: Text('H.264')),
                  PopupMenuItem(value: 'VP8', child: Text('VP8')),
                  PopupMenuItem(value: 'VP9', child: Text('VP9')),
                  PopupMenuItem(value: 'AV1', child: Text('AV1')),
                ],
              ),
            ),
            Divider(color: Colors.white.withOpacity(0.1)),
            SwitchListTile(
              secondary: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.folder_shared,
                    color: Colors.white.withOpacity(0.6), size: 20),
              ),
              title: const Text('Allow remote file manager',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              subtitle: Text(
                  'Two-pane Total Commander–style browser over the same auth',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.45), fontSize: 12)),
              value: rd.fileManagerEnabled,
              activeColor: theme.colorScheme.primary,
              onChanged: provider.setRemoteDesktopFileManagerEnabled,
            ),
            if (rd.fileManagerEnabled)
              SwitchListTile(
                secondary: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.lock_outline,
                      color: Colors.white.withOpacity(0.6), size: 20),
                ),
                title: const Text('File manager — read only',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: Text(
                    'Disable upload, rename, delete and mkdir from viewers',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.45), fontSize: 12)),
                value: rd.fileManagerReadOnly,
                activeColor: theme.colorScheme.primary,
                onChanged: provider.setRemoteDesktopFileManagerReadOnly,
              ),
          ],
        ],
      ),
    );
  }

  String _rdAccessLabel(RemoteDesktopAccessMode m) {
    switch (m) {
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
  
  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
  
  void _showDeviceNameDialog(BuildContext context, AppService appService) {
    final controller = TextEditingController(text: appService.deviceAlias);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Device Name', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter device name',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.7))),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                await appService.setDeviceAlias(newName);
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Device name saved')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showSignalingServerDialog(BuildContext context, RemotePeerProvider peerProvider) {
    final controller = TextEditingController(text: peerProvider.settings.signalingServerUrl);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Signaling Server', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Base URL of the signaling backend. Example: http://127.0.0.1:8787',
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'http://127.0.0.1:8787',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                prefixIcon: Icon(Icons.router, color: Colors.white.withOpacity(0.5)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                ),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.7))),
          ),
          ElevatedButton(
            onPressed: () async {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                await peerProvider.setSignalingServerUrl(value);
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Signaling server saved')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
  
  void _showPasswordDialog(BuildContext context, RemotePeerProvider peerProvider) {
    final controller = TextEditingController(text: peerProvider.settings.connectionPassword ?? '');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Connection Password', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Set a password that others will need to connect to your device',
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enter password',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                prefixIcon: Icon(Icons.lock_outline, color: Colors.white.withOpacity(0.5)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                ),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.7))),
          ),
          if (peerProvider.settings.connectionPassword?.isNotEmpty == true)
            TextButton(
              onPressed: () async {
                await peerProvider.setConnectionPassword(null);
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password removed')),
                  );
                }
              },
              child: Text('Remove', style: TextStyle(color: Colors.red.shade300)),
            ),
          ElevatedButton(
            onPressed: () async {
              final password = controller.text.trim();
              if (password.isNotEmpty) {
                await peerProvider.setConnectionPassword(password);
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password saved')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
  
  void _confirmClearChatHistory(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear Chat History', style: TextStyle(color: Colors.white)),
        content: Text(
          'This will delete all chat messages. This action cannot be undone.',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.7))),
          ),
          ElevatedButton(
            onPressed: () async {
              await context.read<ChatProvider>().clearAllHistory();
              if (context.mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Chat history cleared')),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
  
  void _confirmClearReceiveHistory(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear Receive History', style: TextStyle(color: Colors.white)),
        content: Text(
          'This will delete the history of received files. Files on disk will not be deleted.',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.7))),
          ),
          ElevatedButton(
            onPressed: () async {
              await context.read<ReceiveProvider>().clearHistory();
              if (context.mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Receive history cleared')),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
  
  void _confirmClearSendHistory(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear Send History', style: TextStyle(color: Colors.white)),
        content: Text(
          'This will delete the history of sent files.',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.7))),
          ),
          ElevatedButton(
            onPressed: () async {
              await context.read<SendProvider>().clearHistory();
              if (context.mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Send history cleared')),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
  
  void _confirmClearAllHistory(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear All History', style: TextStyle(color: Colors.white)),
        content: Text(
          'This will delete all chat messages and file history. This action cannot be undone.',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.7))),
          ),
          ElevatedButton(
            onPressed: () async {
              final chatProvider = context.read<ChatProvider>();
              final receiveProvider = context.read<ReceiveProvider>();
              final sendProvider = context.read<SendProvider>();
              await chatProvider.clearAllHistory();
              await receiveProvider.clearHistory();
              await sendProvider.clearHistory();
              if (context.mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('All history cleared')),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}
