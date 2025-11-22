import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:scn/services/app_service.dart';
import 'package:scn/providers/device_provider.dart';
import 'package:scn/providers/receive_provider.dart';
import 'package:scn/providers/send_provider.dart';
import 'package:scn/providers/chat_provider.dart';
import 'package:scn/pages/home_page.dart';
import 'package:scn/utils/process_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Kill other instances of scn.exe before starting
  // Uses process creation time to identify and keep the newest (current) process
  if (defaultTargetPlatform == TargetPlatform.windows) {
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
  
  // Initialize services
  final appService = AppService();
  appService.setProviders(
    receiveProvider: receiveProvider,
    chatProvider: chatProvider,
    deviceProvider: deviceProvider,
  );
  
  // Load device alias (or generate if first run)
  await appService.loadDeviceAlias();
  
  try {
    await appService.initialize();
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
      ],
      child: const SCNApp(),
    ),
  );
  
  // Note: Lock file cleanup will happen automatically on next startup
  // if the process is killed, or we can add cleanup in AppService.dispose()
}

class SCNApp extends StatelessWidget {
  const SCNApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SCN - Secure Connection Network',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
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

