import 'package:flutter/material.dart';
import 'package:scn/pages/tabs/receive_tab.dart';
import 'package:scn/pages/tabs/send_tab.dart';
import 'package:scn/pages/tabs/chat_tab.dart';
import 'package:scn/pages/tabs/settings_tab.dart';
import 'package:scn/widgets/scn_logo.dart';

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
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Navigation Rail (desktop)
          NavigationRail(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            extended: MediaQuery.of(context).size.width > 800,
            leading: Column(
              children: [
                const SizedBox(height: 20),
                const SCNLogo(size: 64),
                const SizedBox(height: 20),
              ],
            ),
            destinations: HomeTab.values.map((tab) {
              return NavigationRailDestination(
                icon: Icon(tab.icon),
                label: Text(tab.label),
              );
            }).toList(),
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
                  onDestinationSelected: (index) {
                    setState(() {
                      _currentIndex = index;
                    });
                  },
                  destinations: HomeTab.values.map((tab) {
                    return NavigationDestination(
                      icon: Icon(tab.icon),
                      label: tab.label,
                    );
                  }).toList(),
                ),
              ],
            )
          : null,
    );
  }
}

