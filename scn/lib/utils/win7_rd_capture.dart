import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'package:scn/utils/logger.dart';

/// One display surface for frames RD (physical monitor or virtual desktop).
class Win7MonitorInfo {
  final int index; // >=0 physical, -1 = all displays
  final int left;
  final int top;
  final int width;
  final int height;
  final bool primary;
  final String name;

  const Win7MonitorInfo({
    required this.index,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.primary,
    required this.name,
  });

  factory Win7MonitorInfo.fromMap(Map map) {
    return Win7MonitorInfo(
      index: (map['index'] as num?)?.toInt() ?? 0,
      left: (map['left'] as num?)?.toInt() ?? 0,
      top: (map['top'] as num?)?.toInt() ?? 0,
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
      primary: map['primary'] == true,
      name: map['name']?.toString() ?? 'Monitor',
    );
  }

  bool get isPhysical => index >= 0;

  Map<String, dynamic> toJson() => {
        'index': index,
        'left': left,
        'top': top,
        'width': width,
        'height': height,
        'primary': primary,
        'name': name,
      };
}

/// Result of a native GDI screen grab + JPEG encode (`scn/win7_rd`).
class Win7ScreenFrame {
  final Uint8List jpeg;
  final int width;
  final int height;

  const Win7ScreenFrame({
    required this.jpeg,
    required this.width,
    required this.height,
  });
}

/// Win7 (and any Windows) GDI capture via MethodChannel — no WebRTC.
class Win7RdCapture {
  Win7RdCapture._();

  static const _channel = MethodChannel('scn/win7_rd');

  static Future<List<Win7MonitorInfo>> listMonitors() async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('listMonitors');
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map(Win7MonitorInfo.fromMap)
          .toList(growable: false);
    } catch (e) {
      AppLogger.log('Win7RdCapture.listMonitors failed: $e');
      return const [];
    }
  }

  /// Brief tray balloon (works on Win7 without tray_manager).
  static Future<bool> showNotifyBalloon({
    required String title,
    required String body,
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>('showNotifyBalloon', {
        'title': title,
        'body': body,
      });
      return ok == true;
    } catch (e) {
      AppLogger.log('Win7RdCapture.showNotifyBalloon failed: $e');
      return false;
    }
  }

  /// Captures a monitor (or all displays when [monitorIndex] == -1) as JPEG.
  /// [quality] 1..100, [maxWidth] 0 = native width.
  static Future<Win7ScreenFrame?> captureJpeg({
    int quality = 50,
    int maxWidth = 1280,
    int monitorIndex = 0,
  }) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('captureScreenJpeg', {
        'quality': quality,
        'maxWidth': maxWidth,
        'monitorIndex': monitorIndex,
      });
      if (raw is! Map) return null;
      final map = raw.cast<Object?, Object?>();
      final bytes = map['jpeg'];
      if (bytes is! Uint8List) return null;
      final w = (map['width'] as num?)?.toInt() ?? 0;
      final h = (map['height'] as num?)?.toInt() ?? 0;
      if (bytes.isEmpty || w <= 0 || h <= 0) return null;
      return Win7ScreenFrame(jpeg: bytes, width: w, height: h);
    } catch (e) {
      AppLogger.log('Win7RdCapture.captureJpeg failed: $e');
      return null;
    }
  }
}
