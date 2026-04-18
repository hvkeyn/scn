import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

import 'package:scn/models/remote_desktop_models.dart';
import 'package:scn/services/remote_desktop/remote_desktop_protocol.dart';
import 'package:scn/utils/logger.dart';

/// Параметры подключения к удалённому хосту.
class RemoteDesktopConnectParams {
  final String host;
  final int port;
  final String myDeviceId;
  final String myAlias;
  final String? password;
  final bool wantControl;
  final bool wantAudio;
  final bool useHttps;

  const RemoteDesktopConnectParams({
    required this.host,
    required this.port,
    required this.myDeviceId,
    required this.myAlias,
    this.password,
    this.wantControl = false,
    this.wantAudio = false,
    this.useHttps = false,
  });

  String get baseHttpUrl => '${useHttps ? 'https' : 'http'}://$host:$port';
  String get baseWsUrl => '${useHttps ? 'wss' : 'ws'}://$host:$port';
}

/// Клиентская сторона удалённого desktop'а.
/// Создаётся для каждой попытки подключения, после `dispose` нельзя переиспользовать.
class RemoteDesktopClientService extends ChangeNotifier {
  RTCPeerConnection? _pc;
  RTCDataChannel? _inputChannel;
  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;
  final RTCVideoRenderer _videoRenderer = RTCVideoRenderer();
  bool _videoRendererReady = false;
  MediaStream? _remoteStream;

  RemoteDesktopSession? _session;
  String? _sessionToken;
  bool _disposed = false;
  Timer? _statsTimer;
  bool _gotVideoTrack = false;
  bool _peerEverConnected = false;

  RTCVideoRenderer get videoRenderer => _videoRenderer;
  bool get isVideoReady => _videoRendererReady;
  RemoteDesktopSession? get session => _session;
  bool get isStreaming =>
      _session?.status == RemoteDesktopSessionStatus.streaming;

  final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  Stream<String> get errors => _errorController.stream;

  Future<void> _ensureRendererInitialized() async {
    if (!_videoRendererReady) {
      await _videoRenderer.initialize();
      _videoRendererReady = true;
    }
  }

  /// Запросить сессию у хоста через REST + WS.
  Future<bool> connect(RemoteDesktopConnectParams params) async {
    await _ensureRendererInitialized();
    try {
      final reqBody = RemoteDesktopRequest(
        viewerDeviceId: params.myDeviceId,
        viewerAlias: params.myAlias,
        password: params.password,
        wantsControl: params.wantControl,
        wantsAudio: params.wantAudio,
      );

      final response = await http
          .post(
            Uri.parse('${params.baseHttpUrl}/api/rd/request'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(reqBody.toJson()),
          )
          .timeout(const Duration(seconds: 60));

      Map<String, dynamic> json;
      try {
        json = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        _emitError('Invalid response from host (HTTP ${response.statusCode})');
        return false;
      }

      final result = RemoteDesktopRequestResponse.fromJson(json);

      if (result.status != RemoteDesktopRequestStatus.accepted ||
          result.sessionId == null ||
          result.sessionToken == null) {
        _emitError(result.errorMessage ??
            'Host rejected the session (${result.status.name})');
        return false;
      }

      _session = RemoteDesktopSession(
        sessionId: result.sessionId!,
        role: RemoteDesktopRole.viewer,
        peerId: '',
        peerAlias: params.host,
        peerAddress: params.host,
        peerPort: params.port,
        status: RemoteDesktopSessionStatus.negotiating,
        authMode: result.grantsAudio
            ? RemoteDesktopAuthMode.password
            : RemoteDesktopAuthMode.prompt,
        inputMode: result.grantsControl
            ? RemoteDesktopInputMode.full
            : RemoteDesktopInputMode.viewOnly,
        audioEnabled: result.grantsAudio,
        createdAt: DateTime.now(),
      );
      _sessionToken = result.sessionToken;
      notifyListeners();

      await _openWebSocket(params, result);
      return true;
    } catch (e, st) {
      AppLogger.log('RD client connect error: $e\n$st');
      _emitError('Connect error: $e');
      return false;
    }
  }

  Future<void> _openWebSocket(RemoteDesktopConnectParams params,
      RemoteDesktopRequestResponse result) async {
    final wsUri =
        Uri.parse('${params.baseWsUrl}${result.wsPath ?? '/api/rd/ws'}');
    final ws = IOWebSocketChannel.connect(wsUri);
    _ws = ws;

    // hello with sessionId+token
    ws.sink.add(jsonEncode({
      'sessionId': result.sessionId,
      'token': result.sessionToken,
    }));

    _wsSub = ws.stream.listen(
      (data) async {
        try {
          final raw = data is String ? data : utf8.decode(data as List<int>);
          final json = jsonDecode(raw) as Map<String, dynamic>;
          final type = json['type'];
          if (type == RemoteDesktopSignalType.error.name) {
            final msg = (json['payload'] as Map?)?['message']?.toString() ??
                'Signaling error';
            _emitError(msg);
            await _shutdown(RemoteDesktopSessionStatus.failed, error: msg);
            return;
          }
          final signal = RemoteDesktopSignal.fromJson(json);
          await _handleSignal(signal);
        } catch (e) {
          AppLogger.log('RD client WS error: $e');
        }
      },
      onDone: () {
        AppLogger.log('RD client: WS closed by host '
            '(gotVideo=$_gotVideoTrack, everConnected=$_peerEverConnected)');
        if (!_gotVideoTrack && !_peerEverConnected) {
          _emitError(
              'Хост закрыл соединение до того, как пошёл видеопоток. '
              'Проверь на хост-машине: появилось ли окно выбора экрана? '
              'Был ли источник выбран? Не выскакивало ли уведомление об ошибке?');
        }
        _shutdown(RemoteDesktopSessionStatus.closed);
      },
      onError: (e) {
        AppLogger.log('RD client: WS error: $e');
        _emitError('WebSocket error: $e');
        _shutdown(RemoteDesktopSessionStatus.failed, error: e.toString());
      },
      cancelOnError: false,
    );
  }

  Future<void> _handleSignal(RemoteDesktopSignal signal) async {
    switch (signal.type) {
      case RemoteDesktopSignalType.hostReady:
        await _initiateOffer();
        break;
      case RemoteDesktopSignalType.answer:
        final pc = _pc;
        if (pc == null) return;
        await pc.setRemoteDescription(RTCSessionDescription(
          signal.payload['sdp'] as String?,
          signal.payload['type'] as String?,
        ));
        break;
      case RemoteDesktopSignalType.iceCandidate:
        final pc = _pc;
        if (pc == null) return;
        await pc.addCandidate(RTCIceCandidate(
          signal.payload['candidate'] as String?,
          signal.payload['sdpMid'] as String?,
          signal.payload['sdpMLineIndex'] as int?,
        ));
        break;
      case RemoteDesktopSignalType.bye:
        AppLogger.log('RD client: received bye from host '
            '(gotVideo=$_gotVideoTrack)');
        if (!_gotVideoTrack && !_peerEverConnected) {
          _emitError(
              'Хост завершил сессию до старта видеопотока. '
              'Скорее всего на хосте либо отменили выбор экрана, '
              'либо захват экрана не удался.');
        }
        await _shutdown(RemoteDesktopSessionStatus.closed);
        break;
      case RemoteDesktopSignalType.stats:
        final p = signal.payload;
        _session = _session?.copyWith(
          stats: RemoteDesktopStats(
            videoBitrateKbps: (p['videoKbps'] as num?)?.toDouble() ?? 0,
            audioBitrateKbps: (p['audioKbps'] as num?)?.toDouble() ?? 0,
            framesPerSecond: (p['fps'] as num?)?.toDouble() ?? 0,
            packetsLost: (p['lost'] as num?)?.toInt() ?? 0,
            roundTripTimeMs: (p['rtt'] as num?)?.toInt() ?? 0,
            frameWidth: (p['width'] as num?)?.toInt() ?? 0,
            frameHeight: (p['height'] as num?)?.toInt() ?? 0,
            updatedAt: DateTime.now(),
          ),
        );
        notifyListeners();
        break;
      default:
        break;
    }
  }

  Future<void> _initiateOffer() async {
    final iceServers = <Map<String, dynamic>>[
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ],
      },
    ];
    final pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });
    _pc = pc;

    pc.onTrack = (RTCTrackEvent event) {
      AppLogger.log(
          'RD client: onTrack kind=${event.track.kind} streams=${event.streams.length}');
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        _videoRenderer.srcObject = _remoteStream;
        if (event.track.kind == 'video') {
          _gotVideoTrack = true;
        }
        notifyListeners();
      }
    };

    pc.onIceCandidate = (RTCIceCandidate candidate) {
      _ws?.sink.add(jsonEncode(RemoteDesktopSignal(
        type: RemoteDesktopSignalType.iceCandidate,
        payload: {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      ).toJson()));
    };

    pc.onConnectionState = (state) {
      AppLogger.log('RD client: peer connection state = $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _peerEverConnected = true;
        _session = _session?.copyWith(
          status: RemoteDesktopSessionStatus.streaming,
          startedAt: DateTime.now(),
        );
        notifyListeners();
        _startStatsTimer();
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        if (!_peerEverConnected) {
          _emitError(
              'Не удалось установить WebRTC-соединение (ICE failed). '
              'Возможно, фаервол / разные подсети.');
        }
        _shutdown(RemoteDesktopSessionStatus.failed,
            error: 'WebRTC connection failed');
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _shutdown(RemoteDesktopSessionStatus.closed);
      }
    };

    // recvonly transceivers — приём видео, опционально аудио
    await pc.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );
    if (_session?.audioEnabled == true) {
      await pc.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );
    }

    // Создаём DataChannel для input.
    final channel = await pc.createDataChannel(
      'scn-rd-input',
      RTCDataChannelInit()
        ..ordered = true
        ..maxRetransmits = 0,
    );
    _inputChannel = channel;

    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    _ws?.sink.add(jsonEncode(RemoteDesktopSignal(
      type: RemoteDesktopSignalType.offer,
      payload: {
        'sdp': offer.sdp,
        'type': offer.type,
      },
    ).toJson()));
  }

  /// Послать input event на хост (no-op если канал не открыт или нет прав).
  void sendInputEvent(RemoteInputEvent event) {
    if (_session?.inputMode != RemoteDesktopInputMode.full) return;
    final channel = _inputChannel;
    if (channel == null) return;
    if (channel.state != RTCDataChannelState.RTCDataChannelOpen) return;
    channel.send(RTCDataChannelMessage(event.toJsonString()));
  }

  /// Запросить смену качества (новый битрейт/FPS).
  void requestQuality({int? bitrateKbps, int? fps}) {
    _ws?.sink.add(jsonEncode(RemoteDesktopSignal(
      type: RemoteDesktopSignalType.qualityChange,
      payload: {
        if (bitrateKbps != null) 'bitrateKbps': bitrateKbps,
        if (fps != null) 'fps': fps,
      },
    ).toJson()));
  }

  void _startStatsTimer() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final pc = _pc;
      if (pc == null) return;
      try {
        final stats = await pc.getStats();
        double videoKbps = 0;
        double audioKbps = 0;
        double fps = 0;
        int rtt = 0;
        int width = 0;
        int height = 0;
        for (final report in stats) {
          final values = report.values;
          if (report.type == 'inbound-rtp') {
            final kind = values['kind'] ?? values['mediaType'];
            final bytesReceived =
                (values['bytesReceived'] as num?)?.toDouble() ?? 0;
            final kbps = bytesReceived * 8 / 1000 / 2;
            if (kind == 'video') {
              videoKbps = kbps;
              fps = (values['framesPerSecond'] as num?)?.toDouble() ?? fps;
              width = (values['frameWidth'] as num?)?.toInt() ?? width;
              height = (values['frameHeight'] as num?)?.toInt() ?? height;
            } else if (kind == 'audio') {
              audioKbps = kbps;
            }
          } else if (report.type == 'candidate-pair') {
            if (values['state'] == 'succeeded') {
              rtt = (((values['currentRoundTripTime'] as num?)?.toDouble() ??
                          0) *
                      1000)
                  .toInt();
            }
          }
        }
        _session = _session?.copyWith(
          stats: RemoteDesktopStats(
            videoBitrateKbps: videoKbps,
            audioBitrateKbps: audioKbps,
            framesPerSecond: fps,
            roundTripTimeMs: rtt,
            frameWidth: width,
            frameHeight: height,
            updatedAt: DateTime.now(),
          ),
        );
        notifyListeners();
      } catch (_) {}
    });
  }

  void _emitError(String message) {
    if (_errorController.isClosed) return;
    _errorController.add(message);
  }

  Future<void> disconnect() async {
    if (_session != null && _sessionToken != null) {
      try {
        // Best-effort сообщение хосту, что мы уходим.
        _ws?.sink.add(jsonEncode(
            const RemoteDesktopSignal(type: RemoteDesktopSignalType.bye)
                .toJson()));
      } catch (_) {}
    }
    await _shutdown(RemoteDesktopSessionStatus.closed);
  }

  Future<void> _shutdown(RemoteDesktopSessionStatus status,
      {String? error}) async {
    if (_disposed) return;
    _statsTimer?.cancel();
    _statsTimer = null;
    try {
      await _wsSub?.cancel();
    } catch (_) {}
    _wsSub = null;
    try {
      await _ws?.sink.close();
    } catch (_) {}
    _ws = null;
    try {
      await _inputChannel?.close();
    } catch (_) {}
    _inputChannel = null;
    try {
      _videoRenderer.srcObject = null;
    } catch (_) {}
    try {
      await _remoteStream?.dispose();
    } catch (_) {}
    _remoteStream = null;
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
    if (_session != null) {
      _session = _session!.copyWith(
        status: status,
        endedAt: DateTime.now(),
        errorMessage: error,
      );
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _shutdown(RemoteDesktopSessionStatus.closed);
    if (_videoRendererReady) {
      _videoRenderer.dispose();
    }
    _errorController.close();
    super.dispose();
  }
}
