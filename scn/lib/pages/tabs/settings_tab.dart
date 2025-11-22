import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scn/services/app_service.dart';
import 'package:scn/widgets/scn_logo.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final appService = context.watch<AppService>();
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const SCNLogo(size: 40),
            title: const Text('About'),
            subtitle: const Text('SCN 1.0.0'),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationIcon: const SCNLogo(size: 64),
                applicationName: 'SCN',
                applicationVersion: '1.0.0',
                applicationLegalese: '© 2025 SCN Team',
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.dns),
                title: const Text('Server Status'),
                subtitle: Text(appService.running ? 'Running' : 'Stopped'),
                trailing: Switch(
                  value: appService.running,
                  onChanged: (value) async {
                    if (value) {
                      await appService.initialize();
                    } else {
                      await appService.stop();
                    }
                  },
                ),
              ),
              if (appService.running)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Port: ${appService.port}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.devices),
            title: const Text('Device Name'),
            subtitle: Text(appService.deviceAlias),
            trailing: const Icon(Icons.edit),
            onTap: () {
              _showDeviceNameDialog(context, appService);
            },
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.folder),
            title: const Text('Download Directory'),
            subtitle: const Text('Downloads'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // TODO: Implement directory picker
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Directory picker not yet implemented')),
              );
            },
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
        title: const Text('Device Name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter device name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
