import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
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
    final trimmed = code.trim();
    if (trimmed.isEmpty) return null;
    try {
      // Extract URL if embedded in other text (e.g. "Name:\nscn://...")
      final urlMatch = RegExp(r'scn://[^\s]+').firstMatch(trimmed);
      if (urlMatch != null) {
        return _parseUrlCode(urlMatch.group(0)!);
      }
      
      // Support short code format: ALIAS@IP:PORT#SECRET
      final shortCode = _parseShortCode(trimmed);
      if (shortCode != null) return shortCode;
      
      // Fallback to base64 format
      return _parseBase64Code(trimmed);
    } catch (e) {
      debugPrint('Failed to parse invite code: $e');
      return null;
    }
  }
  
  InviteCode? _parseUrlCode(String url) {
    final sessionMatch = RegExp(r'^scn://session/([^?\s]+)').firstMatch(url);
    if (sessionMatch != null) {
      final uri = Uri.parse(url);
      return InviteCode(
        deviceId: '',
        deviceAlias: uri.queryParameters['alias'] ?? 'Unknown',
        publicIp: null,
        publicPort: null,
        localPort: 53318,
        password: uri.queryParameters['pwd'],
        secret: uri.queryParameters['secret'],
        expiresAt: null,
        natType: NatType.unknown,
        transportKind: InviteTransportKind.signalingSession,
        signalingServerUrl: uri.queryParameters['signal'],
        sessionId: sessionMatch.group(1),
        inviteToken: uri.queryParameters['token'],
      );
    }

    // Format: scn://ip:port/deviceId?alias=xxx&secret=xxx
    final uri = Uri.parse(url);
    final ip = uri.host;
    final port = uri.hasPort ? uri.port : null;
    final localPortParam = int.tryParse(uri.queryParameters['lport'] ?? '');
    final localPort = localPortParam ?? port ?? 53318;
    
    return InviteCode(
      deviceId: uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '',
      deviceAlias: uri.queryParameters['alias'] ?? 'Unknown',
      publicIp: ip,
      publicPort: port,
      localPort: localPort,
      password: uri.queryParameters['pwd'],
      secret: uri.queryParameters['secret'],
      expiresAt: null,
      natType: NatType.unknown,
    );
  }

  InviteCode? _parseShortCode(String code) {
    final sessionMatch = RegExp(r'^(.+?)@session:([^#]+)(?:#(.+))?$').firstMatch(code);
    if (sessionMatch != null) {
      final alias = sessionMatch.group(1)?.trim();
      final sessionId = sessionMatch.group(2)?.trim();
      if (sessionId == null || sessionId.isEmpty) return null;

      return InviteCode(
        deviceId: '',
        deviceAlias: (alias == null || alias.isEmpty) ? 'Unknown' : alias,
        publicIp: null,
        publicPort: null,
        localPort: 53318,
        password: null,
        secret: null,
        expiresAt: null,
        natType: NatType.unknown,
        transportKind: InviteTransportKind.signalingSession,
        sessionId: sessionId,
        inviteToken: sessionMatch.group(3),
      );
    }

    // Format: ALIAS@IP:PORT#SECRET (alias may contain spaces)
    final match = RegExp(r'^(.+?)@([0-9\\.]+)(?::(\\d{1,5}))?(?:#(.+))?$')
        .firstMatch(code);
    if (match == null) return null;
    
    final alias = match.group(1)?.trim();
    final ip = match.group(2);
    final port = int.tryParse(match.group(3) ?? '');
    final secret = match.group(4);
    
    if (ip == null || ip.isEmpty) return null;
    
    return InviteCode(
      deviceId: '',
      deviceAlias: (alias == null || alias.isEmpty) ? 'Unknown' : alias,
      publicIp: ip,
      publicPort: port ?? 53318,
      localPort: port ?? 53318,
      password: null,
      secret: secret,
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
enum InviteTransportKind {
  legacyDirect,
  signalingSession,
}

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
  final InviteTransportKind transportKind;
  final String? signalingServerUrl;
  final String? sessionId;
  final String? inviteToken;
  
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
    this.transportKind = InviteTransportKind.legacyDirect,
    this.signalingServerUrl,
    this.sessionId,
    this.inviteToken,
  });
  
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
  bool get hasPassword => password != null && password!.isNotEmpty;
  bool get hasPublicIp => publicIp != null && publicIp!.isNotEmpty;
  bool get usesSignalingSession =>
      transportKind == InviteTransportKind.signalingSession &&
      signalingServerUrl != null &&
      sessionId != null &&
      inviteToken != null;
  
  String get fingerprint => PeerDiscoveryService.generateFingerprint(
    deviceId,
    secret ?? '',
  );
  
  /// Convert to URL format for sharing
  String toUrl() {
    if (usesSignalingSession) {
      final query = <String, String>{
        'alias': deviceAlias,
        'signal': signalingServerUrl!,
        'token': inviteToken!,
        if (secret != null) 'secret': secret!,
        if (password != null) 'pwd': password!,
      };
      final queryStr = query.entries
          .map((entry) => '${entry.key}=${Uri.encodeComponent(entry.value)}')
          .join('&');
      return 'scn://session/${sessionId!}${queryStr.isNotEmpty ? '?$queryStr' : ''}';
    }

    final port = publicPort ?? localPort;
    final host = publicIp ?? 'unknown';
    
    final params = <String, String>{
      'alias': deviceAlias,
      'lport': localPort.toString(),
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
    if (usesSignalingSession) {
      final shortToken = inviteToken!.length > 8
          ? inviteToken!.substring(0, 8)
          : inviteToken!;
      return '$deviceAlias@session:$sessionId#$shortToken';
    }

    // Format: ALIAS@IP:PORT#SECRET
    final port = publicPort ?? localPort;
    final ip = publicIp ?? 'unknown';
    final rawSecret = secret ?? '';
    final shortSecret = rawSecret.length > 6 ? rawSecret.substring(0, 6) : rawSecret;
    
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
    'transportKind': transportKind.name,
    'signalingServerUrl': signalingServerUrl,
    'sessionId': sessionId,
    'inviteToken': inviteToken,
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
      transportKind: InviteTransportKind.values.firstWhere(
        (value) => value.name == json['transportKind'],
        orElse: () => InviteTransportKind.legacyDirect,
      ),
      signalingServerUrl: json['signalingServerUrl'] as String?,
      sessionId: json['sessionId'] as String?,
      inviteToken: json['inviteToken'] as String?,
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

