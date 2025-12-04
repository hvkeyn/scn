import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:scn/services/stun_service.dart';

/// Peer Discovery Service
/// Handles peer discovery through QR codes, invite links, and manual connection
class PeerDiscoveryService {
  final String _deviceId;
  final String _deviceAlias;
  final StunService _stun = StunService();
  
  PeerDiscoveryService({
    required String deviceId,
    required String deviceAlias,
  }) : _deviceId = deviceId, _deviceAlias = deviceAlias;
  
  /// Generate invite code for sharing
  Future<InviteCode> generateInviteCode({
    int localPort = 53318,
    String? password,
    Duration validFor = const Duration(hours: 24),
  }) async {
    // Discover public IP via STUN
    final natInfo = await _stun.discoverNat(localPort: localPort);
    
    final expiresAt = DateTime.now().add(validFor);
    final secret = _generateSecret();
    
    return InviteCode(
      deviceId: _deviceId,
      deviceAlias: _deviceAlias,
      publicIp: natInfo?.publicIp,
      publicPort: natInfo?.publicPort,
      localPort: localPort,
      password: password,
      secret: secret,
      expiresAt: expiresAt,
      natType: natInfo?.natType ?? NatType.unknown,
    );
  }
  
  /// Parse invite code from string
  InviteCode? parseInviteCode(String code) {
    try {
      // Support both URL format and base64 format
      if (code.startsWith('scn://')) {
        return _parseUrlCode(code);
      } else {
        return _parseBase64Code(code);
      }
    } catch (e) {
      print('Failed to parse invite code: $e');
      return null;
    }
  }
  
  InviteCode? _parseUrlCode(String url) {
    // Format: scn://ip:port/deviceId?alias=xxx&secret=xxx
    final uri = Uri.parse(url);
    
    final parts = uri.host.split(':');
    final ip = parts[0];
    final port = parts.length > 1 ? int.tryParse(parts[1]) : uri.port;
    
    return InviteCode(
      deviceId: uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '',
      deviceAlias: uri.queryParameters['alias'] ?? 'Unknown',
      publicIp: ip,
      publicPort: port,
      localPort: port ?? 53318,
      password: uri.queryParameters['pwd'],
      secret: uri.queryParameters['secret'],
      expiresAt: null,
      natType: NatType.unknown,
    );
  }
  
  InviteCode? _parseBase64Code(String base64Code) {
    final jsonStr = utf8.decode(base64Decode(base64Code));
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;
    return InviteCode.fromJson(json);
  }
  
  String _generateSecret() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    return base64Encode(bytes).replaceAll(RegExp(r'[+/=]'), '');
  }
  
  /// Generate fingerprint for device verification
  static String generateFingerprint(String deviceId, String secret) {
    final input = '$deviceId:$secret';
    final hash = sha256.convert(utf8.encode(input));
    return hash.toString().substring(0, 16).toUpperCase();
  }
}

/// Invite code for peer connection
class InviteCode {
  final String deviceId;
  final String deviceAlias;
  final String? publicIp;
  final int? publicPort;
  final int localPort;
  final String? password;
  final String? secret;
  final DateTime? expiresAt;
  final NatType natType;
  
  InviteCode({
    required this.deviceId,
    required this.deviceAlias,
    this.publicIp,
    this.publicPort,
    required this.localPort,
    this.password,
    this.secret,
    this.expiresAt,
    required this.natType,
  });
  
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
  bool get hasPassword => password != null && password!.isNotEmpty;
  bool get hasPublicIp => publicIp != null && publicIp!.isNotEmpty;
  
  String get fingerprint => PeerDiscoveryService.generateFingerprint(
    deviceId,
    secret ?? '',
  );
  
  /// Convert to URL format for sharing
  String toUrl() {
    final port = publicPort ?? localPort;
    final host = publicIp ?? 'unknown';
    
    final params = <String, String>{
      'alias': deviceAlias,
      if (secret != null) 'secret': secret!,
      if (password != null) 'pwd': password!,
    };
    
    // Build URL manually to avoid Uri encoding issues
    final queryStr = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    
    return 'scn://$host:$port/$deviceId${queryStr.isNotEmpty ? '?$queryStr' : ''}';
  }
  
  /// Convert to base64 format for QR code
  String toBase64() {
    return base64Encode(utf8.encode(jsonEncode(toJson())));
  }
  
  /// Convert to short text format for manual entry
  String toShortCode() {
    // Format: ALIAS@IP:PORT#SECRET
    final port = publicPort ?? localPort;
    final ip = publicIp ?? 'unknown';
    final shortSecret = (secret ?? '').substring(0, 6);
    
    return '$deviceAlias@$ip:$port#$shortSecret';
  }
  
  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'deviceAlias': deviceAlias,
    'publicIp': publicIp,
    'publicPort': publicPort,
    'localPort': localPort,
    'password': password,
    'secret': secret,
    'expiresAt': expiresAt?.toIso8601String(),
    'natType': natType.name,
  };
  
  factory InviteCode.fromJson(Map<String, dynamic> json) {
    return InviteCode(
      deviceId: json['deviceId'] as String,
      deviceAlias: json['deviceAlias'] as String,
      publicIp: json['publicIp'] as String?,
      publicPort: json['publicPort'] as int?,
      localPort: json['localPort'] as int? ?? 53318,
      password: json['password'] as String?,
      secret: json['secret'] as String?,
      expiresAt: json['expiresAt'] != null 
          ? DateTime.tryParse(json['expiresAt'] as String)
          : null,
      natType: NatType.values.firstWhere(
        (t) => t.name == json['natType'],
        orElse: () => NatType.unknown,
      ),
    );
  }
  
  @override
  String toString() => 'InviteCode($deviceAlias @ $publicIp:$publicPort)';
}

/// QR code data for peer connection
class QrCodeData {
  final InviteCode invite;
  final String qrString;
  
  QrCodeData({required this.invite})
      : qrString = invite.toBase64();
  
  /// Generate QR code content size estimation
  int get estimatedSize => qrString.length;
  
  /// Check if QR code is too complex
  bool get isTooComplex => estimatedSize > 2000;
  
  /// Get simplified QR data if too complex
  String getSimplifiedQr() {
    if (!isTooComplex) return qrString;
    
    // Use URL format which is shorter
    return invite.toUrl();
  }
}

