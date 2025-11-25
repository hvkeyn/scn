import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scn/services/app_service.dart';
import 'package:scn/providers/remote_peer_provider.dart';
import 'package:scn/widgets/scn_logo.dart';

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
            subtitle: Text('SCN 1.0.0+13', style: TextStyle(color: Colors.white.withOpacity(0.5))),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationIcon: const SCNLogo(size: 64),
                applicationName: 'SCN',
                applicationVersion: '1.0.0+13',
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
        
        const SizedBox(height: 32),
      ],
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
}
