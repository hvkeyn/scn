import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:scn/services/app_service.dart';
import 'package:scn/providers/device_provider.dart';
import 'package:scn/providers/receive_provider.dart';
import 'package:scn/providers/send_provider.dart';
import 'package:scn/providers/chat_provider.dart';
import 'package:scn/providers/remote_peer_provider.dart';
import 'package:scn/pages/home_page.dart';
import 'package:scn/utils/process_manager.dart';
import 'package:scn/utils/test_config.dart';
import 'package:scn/utils/logger.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize file logger
  await AppLogger.init();
  
  // Initialize test config from command line args
  TestConfig.init(args);
  final testConfig = TestConfig.current;
  
  if (testConfig.isTestMode) {
    debugPrint('╔══════════════════════════════════════╗');
    debugPrint('║  TEST MODE - Instance #${testConfig.instanceNumber + 1}              ║');
    debugPrint('║  HTTP Port: ${testConfig.httpPort}                   ║');
    debugPrint('║  Mesh Port: ${testConfig.meshPort}                   ║');
    debugPrint('╚══════════════════════════════════════╝');
  }
  
  // Kill other instances only in normal mode (not test mode)
  if (!testConfig.isTestMode && defaultTargetPlatform == TargetPlatform.windows) {
    try {
      final killedCount = await ProcessManager.killOtherInstances();
      if (killedCount > 0) {
        debugPrint('Killed $killedCount other instance(s) of scn.exe');
      }
    } catch (e) {
      // If killing fails, continue anyway - app might still work
      debugPrint('Warning: Could not kill other instances: $e');
    }
  }
  
  // Create providers
  final deviceProvider = DeviceProvider();
  final receiveProvider = ReceiveProvider();
  final sendProvider = SendProvider();
  final chatProvider = ChatProvider();
  final remotePeerProvider = RemotePeerProvider();
  
  // Initialize services
  final appService = AppService();
  appService.setProviders(
    receiveProvider: receiveProvider,
    chatProvider: chatProvider,
    deviceProvider: deviceProvider,
    peerProvider: remotePeerProvider,
  );
  
  // Load device alias (or generate if first run)
  // Test instances automatically get suffix and separate storage
  await appService.loadDeviceAlias();
  
  // Set device ID for all providers (enables per-device storage)
  final deviceId = appService.deviceId;
  final deviceAlias = appService.deviceAlias;
  
  // Set device ID for logger to distinguish processes
  AppLogger.setDeviceId(deviceId);
  AppLogger.log('Device alias: $deviceAlias');
  
  chatProvider.setMyInfo(deviceId: deviceId, alias: deviceAlias);
  receiveProvider.setMyDeviceId(deviceId);
  sendProvider.setMyDeviceId(deviceId);
  
  // Load saved remote peers
  await remotePeerProvider.load();
  
  try {
    // Pass test config port to initialize
    await appService.initialize(port: testConfig.httpPort);
  } catch (e) {
    // If initialization fails, still run the app but show error
    debugPrint('Warning: Failed to initialize services: $e');
    debugPrint('App will continue but some features may not work.');
  }
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appService),
        ChangeNotifierProvider.value(value: deviceProvider),
        ChangeNotifierProvider.value(value: receiveProvider),
        ChangeNotifierProvider.value(value: sendProvider),
        ChangeNotifierProvider.value(value: chatProvider),
        ChangeNotifierProvider.value(value: remotePeerProvider),
      ],
      child: const SCNApp(),
    ),
  );
}

class SCNApp extends StatelessWidget {
  const SCNApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SCN - Secure Connection Network',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366f1),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0f0f23),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1a1a2e),
          foregroundColor: Colors.white,
        ),
        cardTheme: const CardTheme(
          color: Color(0xFF1a1a2e),
        ),
        dialogTheme: const DialogTheme(
          backgroundColor: Color(0xFF1a1a2e),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366f1),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0f0f23),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1a1a2e),
          foregroundColor: Colors.white,
        ),
        cardTheme: const CardTheme(
          color: Color(0xFF1a1a2e),
        ),
        dialogTheme: const DialogTheme(
          backgroundColor: Color(0xFF1a1a2e),
        ),
      ),
      themeMode: ThemeMode.dark,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', ''),
        Locale('ru', ''),
      ],
      home: const HomePage(),
    );
  }
}
