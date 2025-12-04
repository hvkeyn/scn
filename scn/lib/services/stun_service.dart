import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';

/// STUN (Session Traversal Utilities for NAT) Service
/// Used for NAT traversal to enable P2P connections over the internet
class StunService {
  static const List<String> _publicStunServers = [
    'stun.l.google.com:19302',
    'stun1.l.google.com:19302',
    'stun2.l.google.com:19302',
    'stun.cloudflare.com:3478',
    'stun.nextcloud.com:3478',
    'stun.sipnet.ru:3478',
    'stun.ekiga.net:3478',
  ];
  
  /// NAT type detection result
  NatInfo? _natInfo;
  NatInfo? get natInfo => _natInfo;
  
  /// Get public IP and port using STUN
  Future<NatInfo?> discoverNat({int localPort = 0}) async {
    // Try STUN servers first
    for (final server in _publicStunServers) {
      try {
        print('Trying STUN server: $server');
        final result = await _queryStunServer(server, localPort);
        if (result != null) {
          print('STUN success: ${result.publicIp}:${result.publicPort}');
          _natInfo = result;
          return result;
        }
      } catch (e) {
        print('STUN query failed for $server: $e');
        continue;
      }
    }
    
    // Fallback to HTTP IP discovery
    print('STUN failed, trying HTTP fallback...');
    final httpResult = await _discoverViaHttp(localPort);
    if (httpResult != null) {
      _natInfo = httpResult;
      return httpResult;
    }
    
    return null;
  }
  
  /// Fallback: Get public IP via HTTP API
  Future<NatInfo?> _discoverViaHttp(int localPort) async {
    final apis = [
      'https://api.ipify.org',
      'https://icanhazip.com',
      'https://ifconfig.me/ip',
      'https://api.my-ip.io/ip',
    ];
    
    for (final api in apis) {
      try {
        print('Trying HTTP API: $api');
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 5);
        
        final request = await client.getUrl(Uri.parse(api));
        final response = await request.close().timeout(const Duration(seconds: 5));
        
        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join();
          final ip = body.trim();
          
          // Validate IP format
          if (RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(ip)) {
            print('HTTP success: $ip');
            return NatInfo(
              publicIp: ip,
              publicPort: localPort, // Can't determine port via HTTP
              natType: NatType.unknown,
            );
          }
        }
      } catch (e) {
        print('HTTP API failed for $api: $e');
        continue;
      }
    }
    
    return null;
  }
  
  Future<NatInfo?> _queryStunServer(String server, int localPort) async {
    final parts = server.split(':');
    final host = parts[0];
    final port = int.parse(parts[1]);
    
    // Resolve hostname
    final addresses = await InternetAddress.lookup(host);
    if (addresses.isEmpty) return null;
    
    final serverAddress = addresses.first;
    
    // Create UDP socket
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, localPort);
    
    try {
      // Build STUN Binding Request
      final request = _buildBindingRequest();
      
      // Send request
      socket.send(request, serverAddress, port);
      
      // Wait for response with timeout
      final completer = Completer<NatInfo?>();
      Timer? timeout;
      
      timeout = Timer(const Duration(seconds: 5), () {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      });
      
      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram != null) {
            final response = _parseBindingResponse(datagram.data);
            if (response != null && !completer.isCompleted) {
              timeout?.cancel();
              completer.complete(response);
            }
          }
        }
      });
      
      return await completer.future;
    } finally {
      socket.close();
    }
  }
  
  /// Build STUN Binding Request message
  Uint8List _buildBindingRequest() {
    final buffer = BytesBuilder();
    
    // Message Type: Binding Request (0x0001)
    buffer.addByte(0x00);
    buffer.addByte(0x01);
    
    // Message Length: 0 (no attributes)
    buffer.addByte(0x00);
    buffer.addByte(0x00);
    
    // Magic Cookie: 0x2112A442
    buffer.addByte(0x21);
    buffer.addByte(0x12);
    buffer.addByte(0xA4);
    buffer.addByte(0x42);
    
    // Transaction ID: 12 random bytes
    final random = Random.secure();
    for (int i = 0; i < 12; i++) {
      buffer.addByte(random.nextInt(256));
    }
    
    return buffer.toBytes();
  }
  
  /// Parse STUN Binding Response
  NatInfo? _parseBindingResponse(Uint8List data) {
    if (data.length < 20) return null;
    
    // Check message type: Binding Success Response (0x0101)
    if (data[0] != 0x01 || data[1] != 0x01) return null;
    
    // Parse attributes
    int offset = 20; // Skip header
    String? publicIp;
    int? publicPort;
    
    while (offset + 4 <= data.length) {
      final attrType = (data[offset] << 8) | data[offset + 1];
      final attrLength = (data[offset + 2] << 8) | data[offset + 3];
      offset += 4;
      
      if (offset + attrLength > data.length) break;
      
      // XOR-MAPPED-ADDRESS (0x0020)
      if (attrType == 0x0020 && attrLength >= 8) {
        // Skip first byte (reserved), get family
        final family = data[offset + 1];
        
        if (family == 0x01) {
          // IPv4
          // XOR port with magic cookie high bytes
          publicPort = ((data[offset + 2] ^ 0x21) << 8) | (data[offset + 3] ^ 0x12);
          
          // XOR IP with magic cookie
          final ip1 = data[offset + 4] ^ 0x21;
          final ip2 = data[offset + 5] ^ 0x12;
          final ip3 = data[offset + 6] ^ 0xA4;
          final ip4 = data[offset + 7] ^ 0x42;
          
          publicIp = '$ip1.$ip2.$ip3.$ip4';
        }
      }
      // MAPPED-ADDRESS (0x0001) - fallback for older servers
      else if (attrType == 0x0001 && attrLength >= 8 && publicIp == null) {
        final family = data[offset + 1];
        
        if (family == 0x01) {
          // IPv4
          publicPort = (data[offset + 2] << 8) | data[offset + 3];
          publicIp = '${data[offset + 4]}.${data[offset + 5]}.${data[offset + 6]}.${data[offset + 7]}';
        }
      }
      
      // Move to next attribute (with padding to 4-byte boundary)
      offset += (attrLength + 3) & ~3;
    }
    
    if (publicIp != null && publicPort != null) {
      return NatInfo(
        publicIp: publicIp,
        publicPort: publicPort,
        natType: _detectNatType(publicIp, publicPort),
      );
    }
    
    return null;
  }
  
  NatType _detectNatType(String publicIp, int publicPort) {
    // Basic detection - for full detection need multiple STUN queries
    // This is simplified version
    return NatType.unknown;
  }
  
  /// Perform UDP hole punching to establish P2P connection
  Future<RawDatagramSocket?> punchHole({
    required String peerPublicIp,
    required int peerPublicPort,
    int localPort = 0,
    int attempts = 10,
    Duration interval = const Duration(milliseconds: 100),
  }) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, localPort);
    
    try {
      final peerAddress = InternetAddress(peerPublicIp);
      
      // Send multiple packets to punch hole
      for (int i = 0; i < attempts; i++) {
        // Send hole punch packet
        socket.send(
          Uint8List.fromList([0x00, 0x01, 0x02, 0x03]), // Punch packet
          peerAddress,
          peerPublicPort,
        );
        
        await Future.delayed(interval);
      }
      
      // If we get here, hole might be punched
      // Return socket for further communication
      return socket;
    } catch (e) {
      socket.close();
      print('Hole punching failed: $e');
      return null;
    }
  }
  
  /// Generate connection info for sharing
  ConnectionInfo generateConnectionInfo(int localPort) {
    final nat = _natInfo;
    return ConnectionInfo(
      publicIp: nat?.publicIp,
      publicPort: nat?.publicPort,
      localPort: localPort,
      natType: nat?.natType ?? NatType.unknown,
    );
  }
}

/// NAT type classification
enum NatType {
  unknown,
  openInternet,      // No NAT
  fullCone,          // Full Cone NAT (easy P2P)
  restrictedCone,    // Restricted Cone NAT
  portRestricted,    // Port Restricted Cone NAT
  symmetric,         // Symmetric NAT (hard P2P, needs relay)
}

/// NAT discovery result
class NatInfo {
  final String publicIp;
  final int publicPort;
  final NatType natType;
  
  NatInfo({
    required this.publicIp,
    required this.publicPort,
    required this.natType,
  });
  
  @override
  String toString() => 'NAT: $publicIp:$publicPort ($natType)';
}

/// Connection info for P2P
class ConnectionInfo {
  final String? publicIp;
  final int? publicPort;
  final int localPort;
  final NatType natType;
  
  ConnectionInfo({
    this.publicIp,
    this.publicPort,
    required this.localPort,
    required this.natType,
  });
  
  /// Generate shareable connection string
  String toShareString() {
    if (publicIp != null && publicPort != null) {
      return 'scn://$publicIp:$publicPort';
    }
    return 'scn://unknown:$localPort';
  }
  
  /// Parse connection string
  static ConnectionInfo? fromShareString(String str) {
    if (!str.startsWith('scn://')) return null;
    
    final uri = str.substring(6);
    final parts = uri.split(':');
    if (parts.length != 2) return null;
    
    return ConnectionInfo(
      publicIp: parts[0],
      publicPort: int.tryParse(parts[1]),
      localPort: 0,
      natType: NatType.unknown,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'publicIp': publicIp,
    'publicPort': publicPort,
    'localPort': localPort,
    'natType': natType.name,
  };
}

