import 'dart:convert';
import 'package:scn/models/device.dart';

/// Protocol type for device communication
enum ProtocolType {
  http,
  https,
}

/// Multicast DTO for device discovery
class MulticastDto {
  final String alias;
  final String? version;
  final String? deviceModel;
  final DeviceType? deviceType;
  final String fingerprint;
  final int? port;
  final ProtocolType? protocol;
  final bool? download;
  final bool? announcement;
  final bool? announce;

  MulticastDto({
    required this.alias,
    required this.version,
    required this.deviceModel,
    required this.deviceType,
    required this.fingerprint,
    required this.port,
    required this.protocol,
    required this.download,
    required this.announcement,
    required this.announce,
  });

  Map<String, dynamic> toJson() {
    return {
      'alias': alias,
      'version': version,
      'deviceModel': deviceModel,
      'deviceType': deviceType?.name,
      'fingerprint': fingerprint,
      'port': port,
      'protocol': protocol?.name,
      'download': download,
      'announcement': announcement,
      'announce': announce,
    };
  }

  factory MulticastDto.fromJson(Map<String, dynamic> json) {
    return MulticastDto(
      alias: json['alias'] as String,
      version: json['version'] as String?,
      deviceModel: json['deviceModel'] as String?,
      deviceType: json['deviceType'] != null
          ? DeviceType.values.firstWhere(
              (e) => e.name == json['deviceType'],
              orElse: () => DeviceType.desktop,
            )
          : null,
      fingerprint: json['fingerprint'] as String,
      port: json['port'] as int?,
      protocol: json['protocol'] != null
          ? ProtocolType.values.firstWhere(
              (e) => e.name == json['protocol'],
              orElse: () => ProtocolType.http,
            )
          : null,
      download: json['download'] as bool?,
      announcement: json['announcement'] as bool?,
      announce: json['announce'] as bool?,
    );
  }

  Device toDevice(String ip, int ownPort, bool ownHttps) {
    return Device(
      id: fingerprint,
      alias: alias,
      ip: ip,
      port: port ?? ownPort,
      type: deviceType ?? DeviceType.desktop,
    );
  }

  List<int> toBytes() {
    return utf8.encode(jsonEncode(toJson()));
  }
}

