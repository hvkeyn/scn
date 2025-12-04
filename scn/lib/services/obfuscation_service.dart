import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Traffic Obfuscation Service
/// Disguises P2P traffic to bypass DPI (Deep Packet Inspection)
class ObfuscationService {
  final Random _random = Random.secure();
  
  /// Obfuscation protocol type
  ObfuscationType _type = ObfuscationType.websocket;
  ObfuscationType get type => _type;
  
  void setType(ObfuscationType type) {
    _type = type;
  }
  
  /// Wrap data with obfuscation layer
  Uint8List obfuscate(Uint8List data) {
    switch (_type) {
      case ObfuscationType.none:
        return data;
      case ObfuscationType.websocket:
        return _wrapWebSocket(data);
      case ObfuscationType.http:
        return _wrapHttp(data);
      case ObfuscationType.tls:
        return _wrapTlsRecord(data);
      case ObfuscationType.xor:
        return _xorObfuscate(data);
    }
  }
  
  /// Unwrap obfuscated data
  Uint8List? deobfuscate(Uint8List data) {
    switch (_type) {
      case ObfuscationType.none:
        return data;
      case ObfuscationType.websocket:
        return _unwrapWebSocket(data);
      case ObfuscationType.http:
        return _unwrapHttp(data);
      case ObfuscationType.tls:
        return _unwrapTlsRecord(data);
      case ObfuscationType.xor:
        return _xorDeobfuscate(data);
    }
  }
  
  /// WebSocket frame wrapper - looks like normal WebSocket traffic
  Uint8List _wrapWebSocket(Uint8List data) {
    final buffer = BytesBuilder();
    
    // WebSocket frame header
    // FIN + opcode binary (0x82)
    buffer.addByte(0x82);
    
    // Length
    if (data.length <= 125) {
      buffer.addByte(data.length);
    } else if (data.length <= 65535) {
      buffer.addByte(126);
      buffer.addByte((data.length >> 8) & 0xFF);
      buffer.addByte(data.length & 0xFF);
    } else {
      buffer.addByte(127);
      // 8-byte length
      for (int i = 7; i >= 0; i--) {
        buffer.addByte((data.length >> (i * 8)) & 0xFF);
      }
    }
    
    buffer.add(data);
    return buffer.toBytes();
  }
  
  Uint8List? _unwrapWebSocket(Uint8List data) {
    if (data.length < 2) return null;
    
    // Skip opcode byte
    int offset = 1;
    int length = data[1] & 0x7F;
    
    if (length == 126) {
      if (data.length < 4) return null;
      length = (data[2] << 8) | data[3];
      offset = 4;
    } else if (length == 127) {
      if (data.length < 10) return null;
      length = 0;
      for (int i = 0; i < 8; i++) {
        length = (length << 8) | data[2 + i];
      }
      offset = 10;
    } else {
      offset = 2;
    }
    
    if (data.length < offset + length) return null;
    return data.sublist(offset, offset + length);
  }
  
  /// HTTP wrapper - disguise as HTTP POST request/response
  Uint8List _wrapHttp(Uint8List data) {
    final encodedData = base64Encode(data);
    final boundary = _generateBoundary();
    
    final http = '''POST /api/v1/sync HTTP/1.1\r
Host: cloud-sync.example.com\r
Content-Type: multipart/form-data; boundary=$boundary\r
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36\r
Accept: application/json\r
Content-Length: ${encodedData.length + boundary.length * 2 + 50}\r
\r
--$boundary\r
Content-Disposition: form-data; name="data"\r
\r
$encodedData\r
--$boundary--\r
''';
    
    return Uint8List.fromList(utf8.encode(http));
  }
  
  Uint8List? _unwrapHttp(Uint8List data) {
    final str = utf8.decode(data, allowMalformed: true);
    
    // Find the base64 data between boundaries
    final dataStart = str.indexOf('name="data"');
    if (dataStart == -1) return null;
    
    final contentStart = str.indexOf('\r\n\r\n', dataStart);
    if (contentStart == -1) return null;
    
    final contentEnd = str.indexOf('\r\n--', contentStart + 4);
    if (contentEnd == -1) return null;
    
    final base64Data = str.substring(contentStart + 4, contentEnd);
    
    try {
      return base64Decode(base64Data);
    } catch (e) {
      return null;
    }
  }
  
  /// TLS record wrapper - looks like TLS application data
  Uint8List _wrapTlsRecord(Uint8List data) {
    final buffer = BytesBuilder();
    
    // TLS Record Header
    // Content Type: Application Data (0x17)
    buffer.addByte(0x17);
    
    // Version: TLS 1.2 (0x0303)
    buffer.addByte(0x03);
    buffer.addByte(0x03);
    
    // Length (2 bytes, big endian)
    buffer.addByte((data.length >> 8) & 0xFF);
    buffer.addByte(data.length & 0xFF);
    
    // Add XOR-encrypted payload to look like encrypted data
    final key = _generateRandomKey(16);
    buffer.add(key);
    
    for (int i = 0; i < data.length; i++) {
      buffer.addByte(data[i] ^ key[i % key.length]);
    }
    
    return buffer.toBytes();
  }
  
  Uint8List? _unwrapTlsRecord(Uint8List data) {
    if (data.length < 21) return null; // 5 header + 16 key + at least 1 byte
    
    // Skip TLS header (5 bytes)
    final key = data.sublist(5, 21);
    final payload = data.sublist(21);
    
    final result = Uint8List(payload.length);
    for (int i = 0; i < payload.length; i++) {
      result[i] = payload[i] ^ key[i % key.length];
    }
    
    return result;
  }
  
  /// Simple XOR obfuscation with random padding
  Uint8List _xorObfuscate(Uint8List data) {
    final key = _generateRandomKey(32);
    final paddingLen = _random.nextInt(64);
    final padding = _generateRandomKey(paddingLen);
    
    final buffer = BytesBuilder();
    
    // Header: key length (1 byte) + padding length (1 byte)
    buffer.addByte(key.length);
    buffer.addByte(paddingLen);
    
    // Key
    buffer.add(key);
    
    // Random padding
    buffer.add(padding);
    
    // XOR encrypted data
    for (int i = 0; i < data.length; i++) {
      buffer.addByte(data[i] ^ key[i % key.length]);
    }
    
    return buffer.toBytes();
  }
  
  Uint8List? _xorDeobfuscate(Uint8List data) {
    if (data.length < 2) return null;
    
    final keyLen = data[0];
    final paddingLen = data[1];
    
    if (data.length < 2 + keyLen + paddingLen) return null;
    
    final key = data.sublist(2, 2 + keyLen);
    final payload = data.sublist(2 + keyLen + paddingLen);
    
    final result = Uint8List(payload.length);
    for (int i = 0; i < payload.length; i++) {
      result[i] = payload[i] ^ key[i % key.length];
    }
    
    return result;
  }
  
  String _generateBoundary() {
    final bytes = _generateRandomKey(16);
    return '----WebKitFormBoundary${base64Encode(bytes).replaceAll(RegExp(r'[+/=]'), '')}';
  }
  
  Uint8List _generateRandomKey(int length) {
    return Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));
  }
  
  /// Generate fake HTTP headers to bypass DPI
  static Map<String, String> generateFakeHeaders() {
    final userAgents = [
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0',
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15',
    ];
    
    final hosts = [
      'cdn.cloudflare.com',
      'api.github.com',
      'storage.googleapis.com',
      'ajax.googleapis.com',
    ];
    
    final random = Random();
    return {
      'User-Agent': userAgents[random.nextInt(userAgents.length)],
      'Host': hosts[random.nextInt(hosts.length)],
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'en-US,en;q=0.9',
      'Connection': 'keep-alive',
      'Cache-Control': 'no-cache',
    };
  }
}

/// Obfuscation types for different scenarios
enum ObfuscationType {
  none,       // No obfuscation
  websocket,  // WebSocket framing (default, works with most proxies)
  http,       // HTTP POST (bypasses basic DPI)
  tls,        // Fake TLS record (looks like HTTPS)
  xor,        // XOR with random padding (simple obfuscation)
}

/// VLESS-like protocol for advanced obfuscation
class VlessProtocol {
  final String uuid;
  final ObfuscationService _obfuscation = ObfuscationService();
  
  VlessProtocol({required this.uuid}) {
    _obfuscation.setType(ObfuscationType.tls);
  }
  
  /// Create VLESS request header
  Uint8List createRequest(String destHost, int destPort, Uint8List payload) {
    final buffer = BytesBuilder();
    
    // Version
    buffer.addByte(0x00);
    
    // UUID (16 bytes)
    final uuidBytes = _parseUuid(uuid);
    buffer.add(uuidBytes);
    
    // Addons length
    buffer.addByte(0x00);
    
    // Command: TCP (0x01)
    buffer.addByte(0x01);
    
    // Port (2 bytes, big endian)
    buffer.addByte((destPort >> 8) & 0xFF);
    buffer.addByte(destPort & 0xFF);
    
    // Address type: Domain (0x02)
    buffer.addByte(0x02);
    
    // Domain length + domain
    final domainBytes = utf8.encode(destHost);
    buffer.addByte(domainBytes.length);
    buffer.add(domainBytes);
    
    // Payload
    buffer.add(payload);
    
    return _obfuscation.obfuscate(buffer.toBytes());
  }
  
  /// Parse VLESS request
  VlessRequest? parseRequest(Uint8List data) {
    final deobfuscated = _obfuscation.deobfuscate(data);
    if (deobfuscated == null || deobfuscated.length < 18) return null;
    
    try {
      int offset = 0;
      
      // Version
      final version = deobfuscated[offset++];
      if (version != 0x00) return null;
      
      // UUID
      final requestUuid = _formatUuid(deobfuscated.sublist(offset, offset + 16));
      offset += 16;
      
      // Verify UUID
      if (requestUuid != uuid) return null;
      
      // Skip addons
      final addonsLen = deobfuscated[offset++];
      offset += addonsLen;
      
      // Command
      final command = deobfuscated[offset++];
      
      // Port
      final port = (deobfuscated[offset] << 8) | deobfuscated[offset + 1];
      offset += 2;
      
      // Address type
      final addrType = deobfuscated[offset++];
      
      String host;
      if (addrType == 0x01) {
        // IPv4
        host = '${deobfuscated[offset]}.${deobfuscated[offset + 1]}.${deobfuscated[offset + 2]}.${deobfuscated[offset + 3]}';
        offset += 4;
      } else if (addrType == 0x02) {
        // Domain
        final domainLen = deobfuscated[offset++];
        host = utf8.decode(deobfuscated.sublist(offset, offset + domainLen));
        offset += domainLen;
      } else {
        return null;
      }
      
      // Payload
      final payload = deobfuscated.sublist(offset);
      
      return VlessRequest(
        uuid: requestUuid,
        command: command,
        host: host,
        port: port,
        payload: payload,
      );
    } catch (e) {
      return null;
    }
  }
  
  Uint8List _parseUuid(String uuid) {
    final hex = uuid.replaceAll('-', '');
    final bytes = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
  
  String _formatUuid(Uint8List bytes) {
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
  
  /// Generate new UUID
  static String generateUuid() {
    final random = Random.secure();
    final bytes = Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));
    
    // Set version 4
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    // Set variant
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

class VlessRequest {
  final String uuid;
  final int command;
  final String host;
  final int port;
  final Uint8List payload;
  
  VlessRequest({
    required this.uuid,
    required this.command,
    required this.host,
    required this.port,
    required this.payload,
  });
}

