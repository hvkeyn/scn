import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:scn/models/device.dart';
import 'package:scn/models/multicast_dto.dart';
import 'package:scn/services/http_client_service.dart';
import 'package:scn/providers/device_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';

/// Device discovery service using UDP multicast (replaces Rust discovery)
class DiscoveryService {
  final List<RawDatagramSocket> _sockets = [];
  StreamSubscription? _listenerSubscription;
  Timer? _announceTimer;
  final HttpClientService _httpClient = HttpClientService();
  final Uuid _uuid = const Uuid();
  
  DeviceProvider? _deviceProvider;
  String _deviceAlias = 'SCN Device';
  int _devicePort = 53317;
  String _deviceFingerprint = '';
  bool _serverRunning = false;
  
  static const String multicastGroup = '224.0.0.167';
  static const int multicastPort = 53317;
  
  void setProvider(DeviceProvider provider) {
    _deviceProvider = provider;
  }
  
  void setDeviceInfo({String? alias, int? port, String? fingerprint, bool? serverRunning}) {
    if (alias != null) _deviceAlias = alias;
    if (port != null) _devicePort = port;
    if (fingerprint != null) _deviceFingerprint = fingerprint;
    if (serverRunning != null) _serverRunning = serverRunning;
  }
  
  Future<void> start() async {
    if (_sockets.isNotEmpty) return;
    
    try {
      // Generate fingerprint if not set
      if (_deviceFingerprint.isEmpty) {
        _deviceFingerprint = _generateFingerprint();
      }
      
      // Get network interfaces
      final interfaces = await NetworkInterface.list();
      
      // Bind UDP sockets on all interfaces
      for (final interface in interfaces) {
        try {
          // Skip loopback
          if (interface.addresses.any((a) => a.isLoopback)) continue;
          
          final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, multicastPort);
          final multicastAddress = InternetAddress(multicastGroup);
          
          // Join multicast group on this interface
          for (final address in interface.addresses) {
            if (address.type == InternetAddressType.IPv4) {
              try {
                socket.joinMulticast(multicastAddress, interface);
                _sockets.add(socket);
                print('Bound UDP multicast on ${interface.name} (${address.address})');
                break;
              } catch (e) {
                print('Failed to join multicast on ${interface.name}: $e');
              }
            }
          }
        } catch (e) {
          print('Failed to bind socket on ${interface.name}: $e');
        }
      }
      
      if (_sockets.isEmpty) {
        print('No sockets bound, discovery may not work');
        return;
      }
      
      // Listen for incoming multicast messages
      for (final socket in _sockets) {
        socket.listen((RawSocketEvent event) {
          if (event == RawSocketEvent.read) {
            final datagram = socket.receive();
            if (datagram != null) {
              _handleMulticastMessage(datagram);
            }
          }
        });
      }
      
      // Periodically announce this device
      _announceTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        sendAnnouncement();
      });
      
      // Initial announcement
      sendAnnouncement();
      
      print('Discovery service started on port $multicastPort');
    } catch (e) {
      print('Failed to start discovery: $e');
      // Don't rethrow - discovery is optional
    }
  }
  
  void _handleMulticastMessage(Datagram datagram) {
    try {
      final data = utf8.decode(datagram.data);
      final json = jsonDecode(data) as Map<String, dynamic>;
      final dto = MulticastDto.fromJson(json);
      
      // Ignore our own messages
      if (dto.fingerprint == _deviceFingerprint) {
        return;
      }
      
      final ip = datagram.address.address;
      // Use port from announcement, not our own port!
      final device = dto.toDevice(ip, dto.port ?? _devicePort, false);
      
      // Add or update device
      _deviceProvider?.addDevice(device);
      
      // If this is an announcement and our server is running, respond
      if ((dto.announcement == true || dto.announce == true) && _serverRunning) {
        _answerAnnouncement(device);
      }
    } catch (e) {
      print('Error handling multicast message: $e');
    }
  }
  
  Future<void> _answerAnnouncement(Device peer) async {
    try {
      // Try to respond via HTTP register endpoint
      final registerDto = {
        'alias': _deviceAlias,
        'version': '2.1',
        'deviceModel': Platform.operatingSystem,
        'deviceType': 'desktop',
        'fingerprint': _deviceFingerprint,
        'port': _devicePort,
        'protocol': 'http',
        'download': true,
      };
      
      final response = await http.post(
        Uri.parse('${peer.url}/api/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(registerDto),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode != 200) {
        throw Exception('Register failed: ${response.statusCode}');
      }
      
      print('Responded to announcement from ${peer.alias} via HTTP');
    } catch (e) {
      // Fallback: respond via UDP
      print('HTTP response failed, responding via UDP: $e');
      _sendMulticastResponse(peer.ip);
    }
  }
  
  void _sendMulticastResponse(String targetIp) {
    final dto = MulticastDto(
      alias: _deviceAlias,
      version: '2.1',
      deviceModel: Platform.operatingSystem,
      deviceType: DeviceType.desktop,
      fingerprint: _deviceFingerprint,
      port: _devicePort,
      protocol: ProtocolType.http,
      download: true,
      announcement: false,
      announce: false,
    );
    
    final data = dto.toBytes();
    final address = InternetAddress(multicastGroup);
    
    for (final socket in _sockets) {
      try {
        socket.send(data, address, multicastPort);
      } catch (e) {
        print('Failed to send multicast response: $e');
      }
    }
  }
  
  void sendAnnouncement() {
    final dto = MulticastDto(
      alias: _deviceAlias,
      version: '2.1',
      deviceModel: Platform.operatingSystem,
      deviceType: DeviceType.desktop,
      fingerprint: _deviceFingerprint,
      port: _devicePort,
      protocol: ProtocolType.http,
      download: true,
      announcement: true,
      announce: true,
    );
    
    final data = dto.toBytes();
    final address = InternetAddress(multicastGroup);
    
    // Send announcement with delays (like original)
    Future.delayed(const Duration(milliseconds: 100), () {
      _sendMulticastData(data, address);
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      _sendMulticastData(data, address);
    });
    Future.delayed(const Duration(milliseconds: 2000), () {
      _sendMulticastData(data, address);
    });
  }
  
  void _sendMulticastData(List<int> data, InternetAddress address) {
    for (final socket in _sockets) {
      try {
        socket.send(data, address, multicastPort);
      } catch (e) {
        print('Failed to send multicast announcement: $e');
      }
    }
  }
  
  String _generateFingerprint() {
    // Generate a unique fingerprint for this device
    final random = _uuid.v4();
    final bytes = utf8.encode('$random-${Platform.operatingSystem}');
    final hash = sha256.convert(bytes);
    return hash.toString().substring(0, 16);
  }
  
  Future<void> stop() async {
    _announceTimer?.cancel();
    _announceTimer = null;
    
    for (final socket in _sockets) {
      socket.close();
    }
    _sockets.clear();
    
    await _listenerSubscription?.cancel();
    _listenerSubscription = null;
    
    _deviceProvider?.clearDevices();
    print('Discovery service stopped');
  }
}
