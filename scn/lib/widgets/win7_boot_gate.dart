import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scn/pages/home_page.dart';
import 'package:scn/services/app_service.dart';
import 'package:scn/utils/logger.dart';

/// Defers the heavy [HomePage] until after the engine paints a minimal first frame.
/// Build 192 baseline: only UI gating — no deferred mesh/tray here.
class Win7BootGate extends StatefulWidget {
  const Win7BootGate({super.key});

  @override
  State<Win7BootGate> createState() => _Win7BootGateState();
}

class _Win7BootGateState extends State<Win7BootGate> {
  bool _showMainUi = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppLogger.log('Win7: first frame done, loading main UI next frame');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        AppLogger.log('Win7: showing main UI');
        setState(() => _showMainUi = true);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showMainUi) {
      return const HomePage();
    }

    final alias = context.watch<AppService>().deviceAlias;
    return ColoredBox(
      color: const Color(0xFF0f0f23),
      child: Center(
        child: Text(
          'SCN\n$alias\nStarting...',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 18),
        ),
      ),
    );
  }
}
