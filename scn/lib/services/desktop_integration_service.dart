import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:launch_at_startup/launch_at_startup.dart' as las;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scn/services/remote_desktop/host_window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class DesktopIntegrationService extends ChangeNotifier
    with TrayListener, WindowListener {
  static const _prefMinimizeToTray = 'desktop_minimize_to_tray';
  static const _prefCloseToTray = 'desktop_close_to_tray';
  static const _prefLaunchAtStartup = 'desktop_launch_at_startup';

  bool _initialized = false;
  bool _trayReady = false;
  bool _exiting = false;

  bool _minimizeToTray = true;
  bool _closeToTray = true;
  bool _launchAtStartup = false;

  bool get available => Platform.isWindows;
  bool get initialized => _initialized;
  bool get trayReady => _trayReady;
  bool get minimizeToTray => _minimizeToTray;
  bool get closeToTray => _closeToTray;
  bool get launchAtStartup => _launchAtStartup;

  Future<void> init() async {
    if (!available) return;

    await _loadPrefs();
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    await _applyCloseBehavior();
    await _initTray();
    await _syncLaunchAtStartup();

    _initialized = true;
    notifyListeners();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _minimizeToTray = prefs.getBool(_prefMinimizeToTray) ?? true;
    _closeToTray = prefs.getBool(_prefCloseToTray) ?? true;
    _launchAtStartup = prefs.getBool(_prefLaunchAtStartup) ?? false;
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _applyCloseBehavior() async {
    if (!available) return;
    await windowManager.setPreventClose(_closeToTray);
  }

  Future<void> _initTray() async {
    try {
      final iconPath = await _prepareTrayIcon();
      await trayManager.setIcon(iconPath);
      await trayManager.setToolTip('SCN');
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'show', label: 'Show'),
        MenuItem(key: 'hide', label: 'Hide'),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: 'Exit'),
      ]));
      trayManager.addListener(this);
      _trayReady = true;
    } catch (e) {
      debugPrint('Tray init failed: $e');
      _trayReady = false;
    }
  }

  Future<String> _prepareTrayIcon() async {
    const assetPath = 'assets/tray_icon.ico';
    final data = await rootBundle.load(assetPath);
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'scn_tray.ico'));
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return file.path;
  }

  Future<void> _syncLaunchAtStartup() async {
    try {
      las.launchAtStartup.setup(
        appName: 'SCN',
        appPath: Platform.resolvedExecutable,
      );
      final enabled = await las.launchAtStartup.isEnabled();
      if (enabled != _launchAtStartup) {
        if (_launchAtStartup) {
          await las.launchAtStartup.enable();
        } else {
          await las.launchAtStartup.disable();
        }
      }
    } catch (e) {
      debugPrint('Launch at startup setup failed: $e');
    }
  }

  Future<void> setMinimizeToTray(bool value) async {
    _minimizeToTray = value;
    await _saveBool(_prefMinimizeToTray, value);
    notifyListeners();
  }

  Future<void> setCloseToTray(bool value) async {
    _closeToTray = value;
    await _saveBool(_prefCloseToTray, value);
    await _applyCloseBehavior();
    notifyListeners();
  }

  Future<void> setLaunchAtStartup(bool value) async {
    _launchAtStartup = value;
    await _saveBool(_prefLaunchAtStartup, value);
    try {
      if (value) {
        await las.launchAtStartup.enable();
      } else {
        await las.launchAtStartup.disable();
      }
    } catch (e) {
      debugPrint('Launch at startup toggle failed: $e');
    }
    notifyListeners();
  }

  Future<void> showWindow() async {
    if (!available) return;
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> hideWindow() async {
    if (!available) return;
    await windowManager.hide();
  }

  Future<void> toggleWindowVisibility() async {
    if (!available) return;
    final isVisible = await windowManager.isVisible();
    if (isVisible) {
      await hideWindow();
    } else {
      await showWindow();
    }
  }

  Future<void> exitApp() async {
    if (!available) return;
    if (_exiting) return;
    _exiting = true;
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  @override
  void onWindowClose() async {
    if (!available) return;
    if (_exiting) return;
    if (!_closeToTray || !_trayReady) {
      await exitApp();
      return;
    }
    await hideWindow();
  }

  @override
  void onWindowMinimize() async {
    if (!available) return;
    if (_minimizeToTray && _trayReady) {
      await hideWindow();
    }
  }

  @override
  void onTrayIconMouseDown() async {
    if (HostWindowManager.hasActiveSessions) {
      HostWindowManager.keepHiddenIfNeeded();
      return;
    }
    await toggleWindowVisibility();
  }

  @override
  void onTrayIconRightMouseDown() async {
    if (HostWindowManager.hasActiveSessions) {
      HostWindowManager.keepHiddenIfNeeded();
      return;
    }
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    if (HostWindowManager.hasActiveSessions && menuItem.key != 'exit') {
      HostWindowManager.keepHiddenIfNeeded();
      return;
    }
    switch (menuItem.key) {
      case 'show':
        await showWindow();
        break;
      case 'hide':
        await hideWindow();
        break;
      case 'exit':
        await exitApp();
        break;
    }
  }

  @override
  void dispose() {
    if (available) {
      trayManager.removeListener(this);
      windowManager.removeListener(this);
    }
    super.dispose();
  }
}
