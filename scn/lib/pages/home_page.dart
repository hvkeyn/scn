import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scn/pages/tabs/receive_tab.dart';
import 'package:scn/pages/tabs/send_tab.dart';
import 'package:scn/pages/tabs/chat_tab.dart';
import 'package:scn/pages/tabs/settings_tab.dart';
import 'package:scn/pages/remote_desktop_page.dart';
import 'package:scn/widgets/scn_logo.dart';
import 'package:scn/providers/chat_provider.dart';
import 'package:scn/providers/receive_provider.dart';
import 'package:scn/services/update_service.dart';
import 'package:scn/utils/test_config.dart';

enum HomeTab {
  receive(Icons.wifi, 'Receive'),
  send(Icons.send, 'Send'),
  chat(Icons.chat, 'Chat'),
  settings(Icons.settings, 'Settings');
  
  const HomeTab(this.icon, this.label);
  final IconData icon;
  final String label;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  Timer? _refreshTimer;
  int _chatBadge = 0;
  int _receiveBadge = 0;
  bool _updateChecked = false;
  bool _updateInProgress = false;
  
  @override
  void initState() {
    super.initState();
    // Refresh badges every 500ms to catch updates from HTTP callbacks
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _updateBadges();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
    });
  }
  
  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
  
  static const int _tabReceive = 0;
  // ignore: unused_field
  static const int _tabSend = 1;
  static const int _tabChat = 2;
  // ignore: unused_field
  static const int _tabRemoteDesktop = 3;
  // ignore: unused_field
  static const int _tabSettings = 4;

  void _updateBadges() {
    final chatProvider = context.read<ChatProvider>();
    final receiveProvider = context.read<ReceiveProvider>();
    
    final newChatBadge = _currentIndex == _tabChat ? 0 : chatProvider.totalUnreadCount;
    final newReceiveBadge = _currentIndex == _tabReceive ? 0 : receiveProvider.unviewedCount;
    
    if (newChatBadge != _chatBadge || newReceiveBadge != _receiveBadge) {
      setState(() {
        _chatBadge = newChatBadge;
        _receiveBadge = newReceiveBadge;
      });
    }
  }

  Future<void> _checkForUpdates() async {
    if (_updateChecked || _updateInProgress) return;
    _updateChecked = true;
    if (TestConfig.current.isTestMode) return;
    final service = UpdateService();
    final info = await service.checkForUpdate();
    if (!mounted || info == null) return;

    final shouldUpdate = await _showUpdateDialog(service, info);
    if (shouldUpdate == true && mounted) {
      _updateInProgress = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Скачивание обновления...')),
      );
      try {
        await service.downloadAndInstall(info);
      } catch (e) {
        _updateInProgress = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка обновления: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<bool?> _showUpdateDialog(UpdateService service, UpdateInfo info) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: !info.mandatory,
      builder: (context) {
        return AlertDialog(
          title: Text('Доступно обновление ${info.displayVersion}'),
          content: SizedBox(
            width: 420,
            child: FutureBuilder<List<String>>(
              future: service.loadChanges(info),
              builder: (context, snapshot) {
                final changes = snapshot.data ?? const [];
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Найдена новая версия приложения.'),
                    const SizedBox(height: 12),
                    if (changes.isNotEmpty) ...[
                      const Text('Список изменений:'),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 180),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: changes
                                .map((line) => Text('• $line'))
                                .toList(),
                          ),
                        ),
                      ),
                    ] else
                      const Text('Список изменений недоступен.'),
                  ],
                );
              },
            ),
          ),
          actions: [
            if (!info.mandatory)
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Позже'),
              ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Обновить'),
            ),
          ],
        );
      },
    );
  }
  
  void _onTabSelected(int index) {
    // Clear badges when entering specific tabs
    if (index == _tabChat && _currentIndex != _tabChat) {
      // Entering Chat tab - mark all as read
      context.read<ChatProvider>().markAllAsRead();
      _chatBadge = 0;
    }
    if (index == _tabReceive && _currentIndex != _tabReceive) {
      // Entering Receive tab - mark as viewed
      context.read<ReceiveProvider>().markAsViewed();
      _receiveBadge = 0;
    }
    
    setState(() {
      _currentIndex = index;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Navigation Rail (desktop)
          NavigationRail(
            selectedIndex: _currentIndex,
            onDestinationSelected: _onTabSelected,
            extended: MediaQuery.of(context).size.width > 800,
            leading: Column(
              children: [
                const SizedBox(height: 20),
                const SCNLogo(size: 64),
                const SizedBox(height: 20),
              ],
            ),
            destinations: [
              // Receive tab with badge
              NavigationRailDestination(
                icon: _buildBadgeIcon(Icons.wifi, _receiveBadge),
                selectedIcon: const Icon(Icons.wifi),
                label: const Text('Receive'),
              ),
              // Send tab
              const NavigationRailDestination(
                icon: Icon(Icons.send),
                label: Text('Send'),
              ),
              // Chat tab with badge
              NavigationRailDestination(
                icon: _buildBadgeIcon(Icons.chat, _chatBadge),
                selectedIcon: const Icon(Icons.chat),
                label: const Text('Chat'),
              ),
              // Remote Desktop tab
              const NavigationRailDestination(
                icon: Icon(Icons.desktop_windows_outlined),
                selectedIcon: Icon(Icons.desktop_windows),
                label: Text('Remote'),
              ),
              // Settings tab
              const NavigationRailDestination(
                icon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
            ],
          ),
          // Content
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: const [
                ReceiveTab(),
                SendTab(),
                ChatTab(),
                RemoteDesktopPage(),
                SettingsTab(),
              ],
            ),
          ),
        ],
      ),
      // Bottom Navigation (mobile)
      bottomNavigationBar: MediaQuery.of(context).size.width < 600
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: const SCNLogo(size: 40, showText: true),
                ),
                NavigationBar(
                  selectedIndex: _currentIndex,
                  onDestinationSelected: _onTabSelected,
                  destinations: [
                    NavigationDestination(
                      icon: _buildBadgeIcon(Icons.wifi, _receiveBadge),
                      label: 'Receive',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.send),
                      label: 'Send',
                    ),
                    NavigationDestination(
                      icon: _buildBadgeIcon(Icons.chat, _chatBadge),
                      label: 'Chat',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.desktop_windows_outlined),
                      selectedIcon: Icon(Icons.desktop_windows),
                      label: 'Remote',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.settings),
                      label: 'Settings',
                    ),
                  ],
                ),
              ],
            )
          : null,
    );
  }
  
  Widget _buildBadgeIcon(IconData icon, int count) {
    if (count == 0) {
      return Icon(icon);
    }
    
    return Badge(
      label: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(fontSize: 10),
      ),
      backgroundColor: Colors.red,
      child: Icon(icon),
    );
  }
}
