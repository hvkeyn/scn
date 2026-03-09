import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class EmbeddedSignalingServerService {
  final Uuid _uuid = const Uuid();
  final Router _router = Router();
  final _EmbeddedSessionRegistry _sessions = _EmbeddedSessionRegistry();
  HttpServer? _server;

  EmbeddedSignalingServerService() {
    _setupRoutes();
  }

  bool get isRunning => _server != null;
  int? get port => _server?.port;
  String? get localBaseUrl =>
      _server == null ? null : 'http://127.0.0.1:${_server!.port}';

  Future<void> start({int preferredPort = 8787}) async {
    if (_server != null) return;

    final handler = Pipeline()
        .addMiddleware(logRequests())
        .addHandler(_router.call);

    final portsToTry = [
      preferredPort,
      preferredPort + 1,
      preferredPort + 2,
      preferredPort + 3,
    ];

    SocketException? lastError;
    for (final tryPort in portsToTry) {
      try {
        _server = await shelf_io.serve(
          handler,
          InternetAddress.anyIPv4,
          tryPort,
        );
        return;
      } on SocketException catch (error) {
        lastError = error;
      }
    }

    throw lastError ?? StateError('Unable to start embedded signaling server');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  void _setupRoutes() {
    _router.get('/api/v1/health', (Request request) {
      return Response.ok(
        jsonEncode({
          'status': 'ok',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    _router.post('/api/v1/sessions', (Request request) async {
      final rawBody = await request.readAsString();
      final body = rawBody.isEmpty
          ? const <String, dynamic>{}
          : jsonDecode(rawBody) as Map<String, dynamic>;

      final deviceId = body['deviceId'] as String? ?? _uuid.v4();
      final deviceAlias = body['deviceAlias'] as String? ?? 'Unknown host';
      final session = _sessions.create(
        deviceId: deviceId,
        deviceAlias: deviceAlias,
        localPort: port ?? 8787,
      );

      return Response.ok(
        jsonEncode(session.toCreateSessionResponse()),
        headers: {'content-type': 'application/json'},
      );
    });

    _router.get('/api/v1/sessions/<sessionId>',
        (Request request, String sessionId) {
      final session = _sessions.get(sessionId);
      if (session == null) {
        return Response.notFound(
          jsonEncode({'error': 'session_not_found'}),
          headers: {'content-type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode({
          'sessionId': session.sessionId,
          'hostConnected': session.hostSocket != null,
          'joinerConnected': session.joinerSocket != null,
          'expiresAt': session.expiresAt.toUtc().toIso8601String(),
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    _router.get(
      '/ws',
      webSocketHandler((WebSocketChannel channel, String? protocol) {
        _EmbeddedSignalSession? session;
        String? activeRole;

        channel.stream.listen(
          (message) {
            final decoded = jsonDecode(message as String) as Map<String, dynamic>;
            final type = decoded['type'] as String? ?? 'error';
            final payload = decoded['payload'] as Map<String, dynamic>? ?? const {};

            if (type == 'hello') {
              final sessionId = payload['sessionId'] as String?;
              final peerId = payload['peerId'] as String?;
              final alias = payload['alias'] as String? ?? 'Unknown peer';
              final role = payload['role'] as String?;
              final token = payload['token'] as String?;

              if (sessionId == null ||
                  peerId == null ||
                  role == null ||
                  token == null) {
                channel.sink.add(jsonEncode({
                  'type': 'error',
                  'payload': {'reason': 'missing_hello_fields'},
                }));
                channel.sink.close();
                return;
              }

              session = _sessions.get(sessionId);
              activeRole = role;
              if (session == null) {
                channel.sink.add(jsonEncode({
                  'type': 'error',
                  'payload': {'reason': 'session_not_found'},
                }));
                channel.sink.close();
                return;
              }

              if (!session!.validate(role: role, token: token)) {
                channel.sink.add(jsonEncode({
                  'type': 'error',
                  'payload': {'reason': 'invalid_token'},
                }));
                channel.sink.close();
                return;
              }

              session!.attach(
                role: role,
                channel: channel,
                peer: _EmbeddedSignalPeer(
                  peerId: peerId,
                  alias: alias,
                  role: role,
                ),
              );

              channel.sink.add(jsonEncode({
                'type': 'welcome',
                'payload': {
                  'sessionId': session!.sessionId,
                  'role': role,
                  'iceServers': session!.iceServers,
                },
              }));

              if (session!.hostPeer != null && session!.joinerPeer != null) {
                session!.broadcastReady();
              }
              return;
            }

            final currentSession = session;
            final currentRole = activeRole;
            if (currentSession == null || currentRole == null) {
              channel.sink.add(jsonEncode({
                'type': 'error',
                'payload': {'reason': 'hello_required_first'},
              }));
              channel.sink.close();
              return;
            }

            currentSession.forward(
              role: currentRole,
              type: type,
              payload: payload,
            );
          },
          onDone: () {
            if (session != null && activeRole != null) {
              session!.detach(activeRole!);
            }
          },
          onError: (_) {
            if (session != null && activeRole != null) {
              session!.detach(activeRole!);
            }
          },
          cancelOnError: true,
        );
      }),
    );
  }
}

class _EmbeddedSessionRegistry {
  final Uuid _uuid = const Uuid();
  final Map<String, _EmbeddedSignalSession> _sessions = {};

  _EmbeddedSignalSession create({
    required String deviceId,
    required String deviceAlias,
    required int localPort,
  }) {
    final sessionId = _uuid.v4();
    final session = _EmbeddedSignalSession(
      sessionId: sessionId,
      hostToken: _randomToken(),
      joinToken: _randomToken(),
      hostDeviceId: deviceId,
      hostAlias: deviceAlias,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
      localPort: localPort,
      iceServers: _buildIceServers(),
    );
    _sessions[sessionId] = session;
    return session;
  }

  _EmbeddedSignalSession? get(String sessionId) {
    final session = _sessions[sessionId];
    if (session == null) return null;
    if (DateTime.now().toUtc().isAfter(session.expiresAt)) {
      _sessions.remove(sessionId);
      return null;
    }
    return session;
  }

  List<Map<String, dynamic>> _buildIceServers() {
    final stunUrls = _csvOrDefault(
      Platform.environment['SCN_STUN_URLS'],
      const [
        'stun:stun.l.google.com:19302',
        'stun:stun1.l.google.com:19302',
        'stun:stun.cloudflare.com:3478',
      ],
    );

    final turnUrls = _csvOrDefault(
      Platform.environment['SCN_TURN_URLS'],
      const [],
    );
    final username = Platform.environment['SCN_TURN_USERNAME'];
    final credential = Platform.environment['SCN_TURN_CREDENTIAL'];

    final servers = <Map<String, dynamic>>[
      {'urls': stunUrls},
    ];

    if (turnUrls.isNotEmpty) {
      servers.add({
        'urls': turnUrls,
        if (username != null && username.isNotEmpty) 'username': username,
        if (credential != null && credential.isNotEmpty) 'credential': credential,
      });
    }

    return servers;
  }

  List<String> _csvOrDefault(String? raw, List<String> fallback) {
    if (raw == null || raw.trim().isEmpty) return fallback;
    return raw
        .split(',')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList();
  }

  String _randomToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

class _EmbeddedSignalPeer {
  final String peerId;
  final String alias;
  final String role;

  const _EmbeddedSignalPeer({
    required this.peerId,
    required this.alias,
    required this.role,
  });

  Map<String, dynamic> toJson() => {
        'peerId': peerId,
        'alias': alias,
        'role': role,
      };
}

class _EmbeddedSignalSession {
  final String sessionId;
  final String hostToken;
  final String joinToken;
  final String hostDeviceId;
  final String hostAlias;
  final DateTime expiresAt;
  final int localPort;
  final List<Map<String, dynamic>> iceServers;

  _EmbeddedSignalPeer? hostPeer;
  _EmbeddedSignalPeer? joinerPeer;
  WebSocketChannel? hostSocket;
  WebSocketChannel? joinerSocket;

  _EmbeddedSignalSession({
    required this.sessionId,
    required this.hostToken,
    required this.joinToken,
    required this.hostDeviceId,
    required this.hostAlias,
    required this.expiresAt,
    required this.localPort,
    required this.iceServers,
  });

  bool validate({required String role, required String token}) {
    if (role == 'host') return token == hostToken;
    if (role == 'joiner') return token == joinToken;
    return false;
  }

  void attach({
    required String role,
    required WebSocketChannel channel,
    required _EmbeddedSignalPeer peer,
  }) {
    if (role == 'host') {
      hostSocket = channel;
      hostPeer = peer;
      return;
    }

    joinerSocket = channel;
    joinerPeer = peer;
    if (hostPeer != null) {
      hostSocket?.sink.add(jsonEncode({
        'type': 'peerJoined',
        'payload': peer.toJson(),
      }));
    }
  }

  void broadcastReady() {
    final host = hostPeer;
    final joiner = joinerPeer;
    if (host == null || joiner == null) return;

    hostSocket?.sink.add(jsonEncode({
      'type': 'ready',
      'payload': joiner.toJson(),
    }));
    joinerSocket?.sink.add(jsonEncode({
      'type': 'ready',
      'payload': host.toJson(),
    }));
  }

  void forward({
    required String role,
    required String type,
    required Map<String, dynamic> payload,
  }) {
    final target = role == 'host' ? joinerSocket : hostSocket;
    target?.sink.add(jsonEncode({
      'type': type,
      'payload': payload,
    }));
  }

  void detach(String role) {
    if (role == 'host') {
      hostSocket = null;
      hostPeer = null;
      joinerSocket?.sink.add(jsonEncode({
        'type': 'peerLeft',
        'payload': {'role': 'host'},
      }));
      return;
    }

    joinerSocket = null;
    joinerPeer = null;
    hostSocket?.sink.add(jsonEncode({
      'type': 'peerLeft',
      'payload': {'role': 'joiner'},
    }));
  }

  Map<String, dynamic> toCreateSessionResponse() => {
        'sessionId': sessionId,
        'hostToken': hostToken,
        'joinToken': joinToken,
        'wsUrl': '/ws',
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'iceServers': iceServers,
      };
}
