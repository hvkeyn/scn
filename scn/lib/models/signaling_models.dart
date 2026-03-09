import 'dart:convert';

enum SignalingMessageType {
  hello,
  welcome,
  ready,
  peerJoined,
  peerLeft,
  offer,
  answer,
  iceCandidate,
  error,
  bye,
  ping,
  pong,
}

class IceServerConfig {
  final List<String> urls;
  final String? username;
  final String? credential;

  const IceServerConfig({
    required this.urls,
    this.username,
    this.credential,
  });

  bool get isTurn =>
      urls.any((url) => url.startsWith('turn:') || url.startsWith('turns:'));

  Map<String, dynamic> toJson() => {
        'urls': urls,
        if (username != null) 'username': username,
        if (credential != null) 'credential': credential,
      };

  factory IceServerConfig.fromJson(Map<String, dynamic> json) {
    final rawUrls = json['urls'];
    final urls = rawUrls is List
        ? rawUrls.map((entry) => entry.toString()).toList()
        : <String>[rawUrls?.toString() ?? ''];

    return IceServerConfig(
      urls: urls.where((value) => value.isNotEmpty).toList(),
      username: json['username'] as String?,
      credential: json['credential'] as String?,
    );
  }
}

class SignalingServerConfig {
  final String apiBaseUrl;
  final String wsBaseUrl;

  const SignalingServerConfig({
    required this.apiBaseUrl,
    required this.wsBaseUrl,
  });

  factory SignalingServerConfig.fromBaseUrl(String baseUrl) {
    final trimmed = baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    if (trimmed.startsWith('ws://') || trimmed.startsWith('wss://')) {
      final wsBase = trimmed;
      final httpBase = trimmed.replaceFirst(RegExp(r'^ws'), 'http');
      return SignalingServerConfig(
        apiBaseUrl: httpBase,
        wsBaseUrl: wsBase,
      );
    }

    final apiBase = trimmed;
    final wsBase = trimmed.replaceFirst(RegExp(r'^http'), 'ws');
    return SignalingServerConfig(
      apiBaseUrl: apiBase,
      wsBaseUrl: wsBase,
    );
  }

  Uri sessionsUri() => Uri.parse('$apiBaseUrl/api/v1/sessions');

  Uri webSocketUri() => Uri.parse('$wsBaseUrl/ws');
}

class SignalingSession {
  final String sessionId;
  final String hostToken;
  final String joinToken;
  final String wsUrl;
  final DateTime? expiresAt;
  final List<IceServerConfig> iceServers;

  const SignalingSession({
    required this.sessionId,
    required this.hostToken,
    required this.joinToken,
    required this.wsUrl,
    required this.iceServers,
    this.expiresAt,
  });

  factory SignalingSession.fromJson(Map<String, dynamic> json) {
    final iceServers = (json['iceServers'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(IceServerConfig.fromJson)
        .toList();

    return SignalingSession(
      sessionId: json['sessionId'] as String,
      hostToken: json['hostToken'] as String,
      joinToken: json['joinToken'] as String,
      wsUrl: json['wsUrl'] as String,
      expiresAt: json['expiresAt'] != null
          ? DateTime.tryParse(json['expiresAt'] as String)
          : null,
      iceServers: iceServers,
    );
  }
}

class SignalingEnvelope {
  final SignalingMessageType type;
  final Map<String, dynamic> payload;

  const SignalingEnvelope({
    required this.type,
    this.payload = const {},
  });

  String encode() => jsonEncode(toJson());

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'payload': payload,
      };

  factory SignalingEnvelope.fromJson(Map<String, dynamic> json) {
    return SignalingEnvelope(
      type: SignalingMessageType.values.firstWhere(
        (value) => value.name == json['type'],
        orElse: () => SignalingMessageType.error,
      ),
      payload: (json['payload'] as Map<String, dynamic>?) ?? const {},
    );
  }

  factory SignalingEnvelope.decode(String raw) {
    return SignalingEnvelope.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}
