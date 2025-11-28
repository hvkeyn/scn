import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scn/pages/tabs/receive_tab.dart';
import 'package:scn/pages/tabs/send_tab.dart';
import 'package:scn/pages/tabs/chat_tab.dart';
import 'package:scn/pages/tabs/settings_tab.dart';
import 'package:scn/widgets/scn_logo.dart';
import 'package:scn/providers/chat_provider.dart';
import 'package:scn/providers/receive_provider.dart';
import 'package:scn/models/session.dart';

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
  
  void _onTabSelected(int index) {
    // Clear badges when entering specific tabs
    if (index == 2 && _currentIndex != 2) {
      // Entering Chat tab - mark all as read
      context.read<ChatProvider>().markAllAsRead();
    }
    
    setState(() {
      _currentIndex = index;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Consumer2<ChatProvider, ReceiveProvider>(
      builder: (context, chatProvider, receiveProvider, child) {
        // Chat badge - show unread count when NOT on chat tab
        final chatUnread = _currentIndex == 2 ? 0 : chatProvider.totalUnreadCount;
        
        // Receive badge - show pending files count when NOT on receive tab
        int pendingFiles = 0;
        if (_currentIndex != 0 && receiveProvider.currentSession != null) {
          pendingFiles = receiveProvider.currentSession!.files.values
              .where((f) => f.status == FileStatus.queue || f.status == FileStatus.receiving)
              .length;
        }
        
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
                    icon: _buildBadgeIcon(Icons.wifi, pendingFiles),
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
                    icon: _buildBadgeIcon(Icons.chat, chatUnread),
                    selectedIcon: const Icon(Icons.chat),
                    label: const Text('Chat'),
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
                          icon: _buildBadgeIcon(Icons.wifi, pendingFiles),
                          label: 'Receive',
                        ),
                        const NavigationDestination(
                          icon: Icon(Icons.send),
                          label: 'Send',
                        ),
                        NavigationDestination(
                          icon: _buildBadgeIcon(Icons.chat, chatUnread),
                          label: 'Chat',
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
      },
    );
  }
  
  Widget _buildBadgeIcon(IconData icon, int count, {bool selected = false}) {
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
