import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scn/pages/tabs/receive_tab.dart';
import 'package:scn/pages/tabs/send_tab.dart';
import 'package:scn/pages/tabs/chat_tab.dart';
import 'package:scn/pages/tabs/settings_tab.dart';
import 'package:scn/widgets/scn_logo.dart';
import 'package:scn/providers/chat_provider.dart';
import 'package:scn/providers/receive_provider.dart';

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
  
  @override
  void initState() {
    super.initState();
    // Refresh badges every 500ms to catch updates from HTTP callbacks
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _updateBadges();
    });
  }
  
  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
  
  void _updateBadges() {
    final chatProvider = context.read<ChatProvider>();
    final receiveProvider = context.read<ReceiveProvider>();
    
    final newChatBadge = _currentIndex == 2 ? 0 : chatProvider.totalUnreadCount;
    final newReceiveBadge = _currentIndex == 0 ? 0 : receiveProvider.unviewedCount;
    
    if (newChatBadge != _chatBadge || newReceiveBadge != _receiveBadge) {
      setState(() {
        _chatBadge = newChatBadge;
        _receiveBadge = newReceiveBadge;
      });
    }
  }
  
  void _onTabSelected(int index) {
    // Clear badges when entering specific tabs
    if (index == 2 && _currentIndex != 2) {
      // Entering Chat tab - mark all as read
      context.read<ChatProvider>().markAllAsRead();
      _chatBadge = 0;
    }
    if (index == 0 && _currentIndex != 0) {
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
