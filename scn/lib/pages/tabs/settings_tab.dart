import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scn/services/app_service.dart';
import 'package:scn/providers/remote_peer_provider.dart';
import 'package:scn/providers/chat_provider.dart';
import 'package:scn/providers/receive_provider.dart';
import 'package:scn/providers/send_provider.dart';
import 'package:scn/models/remote_peer.dart';
import 'package:scn/widgets/scn_logo.dart';
import 'package:scn/utils/test_config.dart';
import 'package:scn/pages/vpn_page.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final appService = context.watch<AppService>();
    final peerProvider = context.watch<RemotePeerProvider>();
    final settings = peerProvider.settings;
    final theme = Theme.of(context);
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // About Section
        _buildCard(
          context,
          child: ListTile(
            leading: const SCNLogo(size: 40),
            title: const Text('About', style: TextStyle(color: Colors.white)),
            subtitle: Text('SCN 1.0.0+18', style: TextStyle(color: Colors.white.withOpacity(0.5))),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationIcon: const SCNLogo(size: 64),
                applicationName: 'SCN',
                applicationVersion: '1.0.0+18',
                applicationLegalese: '© 2025 SCN Team',
              );
            },
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
            title: const Text('Internet VPN (P2P)', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              'Connect to devices over the internet',
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
                          'Make sure these ports are open in your firewall for remote connections',
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
    final instanceNum = await TestConfig.findNextAvailableInstance();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Launching Test Instance #$instanceNum...'),
        backgroundColor: Colors.amber.shade700,
      ),
    );
    
    final success = await TestConfig.launchTestInstance(instanceNum);
    
    if (context.mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Test Instance #$instanceNum launched! Port: ${TestConfig.basePort + (instanceNum * 10)}'),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
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
              await context.read<ChatProvider>().clearAllHistory();
              await context.read<ReceiveProvider>().clearHistory();
              await context.read<SendProvider>().clearHistory();
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
