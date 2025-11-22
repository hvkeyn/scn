/// Device model (simplified)
class Device {
  final String id;
  final String alias;
  final String ip;
  final int port;
  final DeviceType type;
  
  Device({
    required this.id,
    required this.alias,
    required this.ip,
    required this.port,
    required this.type,
  });
  
  String get url => 'http://$ip:$port';
}

enum DeviceType {
  mobile,
  desktop,
  web,
  headless,
  server,
}

