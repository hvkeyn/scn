import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:scn/services/app_service.dart';
import 'package:scn/providers/device_provider.dart';
import 'package:scn/providers/receive_provider.dart';
import 'package:scn/providers/send_provider.dart';
import 'package:scn/providers/chat_provider.dart';
import 'package:scn/pages/home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
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
  await appService.initialize();
  
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

