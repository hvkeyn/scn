import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:scn/models/signaling_models.dart';
import 'package:scn/utils/logger.dart';

class SignalingPeerInfo {
  final String peerId;
  final String alias;
  final String role;

  const SignalingPeerInfo({
    required this.peerId,
    required this.alias,
    required this.role,
  });
}

class SignalingService {
  WebSocket? _socket;
  final _eventsController = StreamController<SignalingEnvelope>.broadcast();

  Stream<SignalingEnvelope> get events => _eventsController.stream;
  bool get isConnected => _socket != null;

  Future<SignalingSession> createSession({
    required SignalingServerConfig config,
    required String deviceId,
    required String deviceAlias,
  }) async {
    final response = await http
        .post(
          config.sessionsUri(),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'deviceId': deviceId,
            'deviceAlias': deviceAlias,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception(
        'Signaling session creation failed: ${response.statusCode}',
      );
    }

    return SignalingSession.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> connect({
    required SignalingServerConfig config,
    required String sessionId,
    required String peerId,
    required String alias,
    required String role,
    required String token,
  }) async {
    await disconnect();

    final uri = config.webSocketUri();

    AppLogger.log('Connecting to signaling server: $uri');
    final socket = await WebSocket.connect(
      uri.toString(),
      customClient: HttpClient()..badCertificateCallback = (_, __, ___) => true,
    ).timeout(const Duration(seconds: 10));

    _socket = socket;
    socket.add(
      SignalingEnvelope(
        type: SignalingMessageType.hello,
        payload: {
          'sessionId': sessionId,
          'peerId': peerId,
          'alias': alias,
          'role': role,
          'token': token,
        },
      ).encode(),
    );
    socket.listen(
      (raw) {
        try {
          final message = SignalingEnvelope.decode(raw as String);
          _eventsController.add(message);
        } catch (e) {
          AppLogger.log('Invalid signaling message: $e');
        }
      },
      onDone: () {
        AppLogger.log('Signaling socket closed');
        _socket = null;
      },
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.log('Signaling socket error: $error');
        _socket = null;
      },
      cancelOnError: true,
    );
  }

  void send(SignalingEnvelope envelope) {
    final socket = _socket;
    if (socket == null) {
      throw StateError('Signaling socket is not connected');
    }
    socket.add(envelope.encode());
  }

  void sendOffer(Map<String, dynamic> offer) {
    send(SignalingEnvelope(type: SignalingMessageType.offer, payload: offer));
  }

  void sendAnswer(Map<String, dynamic> answer) {
    send(SignalingEnvelope(type: SignalingMessageType.answer, payload: answer));
  }

  void sendIceCandidate(Map<String, dynamic> candidate) {
    send(
      SignalingEnvelope(
        type: SignalingMessageType.iceCandidate,
        payload: candidate,
      ),
    );
  }

  void sendBye({String? reason}) {
    send(
      SignalingEnvelope(
        type: SignalingMessageType.bye,
        payload: {if (reason != null) 'reason': reason},
      ),
    );
  }

  Future<void> disconnect() async {
    final socket = _socket;
    _socket = null;
    await socket?.close();
  }

  void dispose() {
    disconnect();
    _eventsController.close();
  }
}
