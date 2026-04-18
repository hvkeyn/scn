import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:scn/models/remote_desktop_models.dart';
import 'package:scn/services/remote_desktop/input_injector/input_injector.dart';
import 'package:scn/services/remote_desktop/remote_desktop_protocol.dart';
import 'package:scn/utils/logger.dart';

/// Внутреннее представление активной хост-сессии.
class _HostSession {
  final String sessionId;
  final String sessionToken;
  final String viewerDeviceId;
  final String viewerAlias;
  final String viewerAddress;
  final RemoteDesktopAuthMode authMode;
  bool grantsControl;
  bool grantsAudio;

  RemoteDesktopSessionStatus status = RemoteDesktopSessionStatus.pendingApproval;
  String? errorMessage;

  RTCPeerConnection? pc;
  RTCDataChannel? inputChannel;
  MediaStream? screenStream;
  WebSocketChannel? ws;
  StreamSubscription? wsSub;
  Timer? statsTimer;
  RemoteDesktopStats? lastStats;

  /// Текущее значение адаптивного потолка битрейта (kbps).
  int currentMaxBitrateKbps = 0;

  /// Текущая оценка целевого fps при адаптации.
  int currentTargetFps = 0;

  /// Последние bytesSent для расчёта delta в _startStatsTimer.
  double lastBytesSent = 0;

  /// Сторона хоста ждёт подтверждения от UI; completer ставится в null после resolve.
  Completer<bool>? approvalCompleter;

  /// Watchdog: если viewer не подключился по WS в течение N секунд после
  /// approval, сессия считается зависшей и автоматически закрывается, чтобы
  /// не блокировать новые запросы.
  Timer? wsConnectWatchdog;

  /// Кнопки мыши, которые сейчас удерживаются viewer'ом. Нужно для аварийного
  /// release при дисконнекте, чтобы кнопка не "залипла" на хосте.
  final Set<RemoteMouseButton> heldMouseButtons = <RemoteMouseButton>{};

  /// Логические клавиши, которые сейчас удерживаются viewer'ом.
  final Set<int> heldKeys = <int>{};

  _HostSession({
    required this.sessionId,
    required this.sessionToken,
    required this.viewerDeviceId,
    required this.viewerAlias,
    required this.viewerAddress,
    required this.authMode,
    required this.grantsControl,
    required this.grantsAudio,
  });

  RemoteDesktopSession toModel() => RemoteDesktopSession(
        sessionId: sessionId,
        role: RemoteDesktopRole.host,
        peerId: viewerDeviceId,
        peerAlias: viewerAlias,
        peerAddress: viewerAddress,
        peerPort: 0,
        status: status,
        authMode: authMode,
        inputMode: grantsControl
            ? RemoteDesktopInputMode.full
            : RemoteDesktopInputMode.viewOnly,
        audioEnabled: grantsAudio,
        createdAt: DateTime.now(),
        errorMessage: errorMessage,
        stats: lastStats,
      );
}

/// Сервис, держит state хоста: принимает RD-запросы, обслуживает RTCPeerConnection,
/// захватывает экран и сводит всё в один live-список сессий.
class RemoteDesktopHostService extends ChangeNotifier {
  final Map<String, _HostSession> _sessions = {};
  final StreamController<RemoteDesktopPermissionRequest> _approvalController =
      StreamController<RemoteDesktopPermissionRequest>.broadcast();
  final Random _random = Random.secure();
  final InputInjector _inputInjector = createInputInjector();

  RemoteDesktopSettings _settings = const RemoteDesktopSettings();
  // ignore: unused_field
  String _myDeviceId = '';
  // ignore: unused_field
  String _myAlias = 'SCN Device';

  /// Стрим запросов на разрешение, на который подписывается UI слой.
  Stream<RemoteDesktopPermissionRequest> get approvalRequests =>
      _approvalController.stream;

  /// Снимок текущих сессий для UI (отсортирован по новизне).
  List<RemoteDesktopSession> get sessions {
    final list =
        _sessions.values.map((s) => s.toModel()).toList(growable: false);
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  bool get hasActiveSession => _sessions.values.any((s) =>
      s.status == RemoteDesktopSessionStatus.streaming ||
      s.status == RemoteDesktopSessionStatus.negotiating);

  /// Применить новые настройки (вызывается после изменения в UI).
  void applySettings(RemoteDesktopSettings settings) {
    _settings = settings;
  }

  void setIdentity({required String deviceId, required String alias}) {
    _myDeviceId = deviceId;
    _myAlias = alias;
  }

  /// Точка входа REST endpoint'а POST /api/rd/request.
  Future<shelf.Response> handleRequest(shelf.Request request) async {
    if (!_settings.enabled ||
        _settings.accessMode == RemoteDesktopAccessMode.disabled) {
      return shelf.Response.forbidden(
        jsonEncode(const RemoteDesktopRequestResponse(
          status: RemoteDesktopRequestStatus.rejected,
          errorMessage: 'Remote desktop is disabled on this device',
        ).toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Если уже есть зависшая сессия от ТОГО ЖЕ viewer'а (он повторно жмёт
    // Connect, не успев увидеть, что предыдущая в negotiating) — закрываем
    // её, чтобы не словить ложный 409.
    Map<String, dynamic>? earlyBody;
    try {
      earlyBody =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return shelf.Response.badRequest(
        body: jsonEncode(const RemoteDesktopRequestResponse(
          status: RemoteDesktopRequestStatus.rejected,
          errorMessage: 'Malformed request body',
        ).toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    }
    final earlyReq = RemoteDesktopRequest.fromJson(earlyBody);

    final stale = _sessions.values
        .where((s) =>
            s.viewerDeviceId == earlyReq.viewerDeviceId &&
            s.status != RemoteDesktopSessionStatus.streaming)
        .toList();
    for (final s in stale) {
      AppLogger.log(
          'RD host: dropping stale session ${s.sessionId} (status=${s.status}) '
          'for viewer ${s.viewerDeviceId} due to new request');
      await _terminate(s, RemoteDesktopSessionStatus.closed);
    }

    if (hasActiveSession) {
      return shelf.Response(409,
          body: jsonEncode(const RemoteDesktopRequestResponse(
            status: RemoteDesktopRequestStatus.busy,
            errorMessage: 'Host is already serving another session',
          ).toJson()),
          headers: {'Content-Type': 'application/json'});
    }

    final req = earlyReq;

    final viewerAddress = _peerAddressFromRequest(request);
    RemoteDesktopAuthMode? authMode;
    bool grantsControl = req.wantsControl && !_settings.viewOnlyByDefault;
    final grantsAudio = req.wantsAudio && _settings.shareAudio;

    final isTrusted =
        _settings.trustedPeerIds.contains(req.viewerDeviceId);
    final passwordOk = req.password != null &&
        _settings.password != null &&
        req.password == _settings.password;

    if (isTrusted) {
      authMode = RemoteDesktopAuthMode.trusted;
    } else if (passwordOk &&
        (_settings.accessMode == RemoteDesktopAccessMode.passwordOnly ||
            _settings.accessMode ==
                RemoteDesktopAccessMode.passwordOrPrompt)) {
      authMode = RemoteDesktopAuthMode.password;
    } else if (_settings.accessMode == RemoteDesktopAccessMode.passwordOnly) {
      return shelf.Response.forbidden(
        jsonEncode(const RemoteDesktopRequestResponse(
          status: RemoteDesktopRequestStatus.rejected,
          errorMessage: 'Invalid password',
        ).toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final sessionId = _generateId();
    final sessionToken = _generateId();

    final session = _HostSession(
      sessionId: sessionId,
      sessionToken: sessionToken,
      viewerDeviceId: req.viewerDeviceId,
      viewerAlias: req.viewerAlias,
      viewerAddress: viewerAddress,
      authMode: authMode ?? RemoteDesktopAuthMode.prompt,
      grantsControl: grantsControl,
      grantsAudio: grantsAudio,
    );
    _sessions[sessionId] = session;
    notifyListeners();

    if (authMode == null) {
      // Нужен явный prompt. Шлём событие в UI и ждём подтверждения.
      session.approvalCompleter = Completer<bool>();
      _approvalController.add(RemoteDesktopPermissionRequest(
        sessionId: sessionId,
        viewerDeviceId: req.viewerDeviceId,
        viewerAlias: req.viewerAlias,
        viewerAddress: viewerAddress,
        requestedMode: RemoteDesktopAuthMode.prompt,
        wantsControl: req.wantsControl,
        requestedAt: DateTime.now(),
      ));

      final approved = await session.approvalCompleter!.future
          .timeout(const Duration(seconds: 30), onTimeout: () => false);
      session.approvalCompleter = null;

      if (!approved) {
        await _terminate(session, RemoteDesktopSessionStatus.rejected,
            error: 'Host did not approve');
        return shelf.Response.forbidden(
          jsonEncode(const RemoteDesktopRequestResponse(
            status: RemoteDesktopRequestStatus.rejected,
            errorMessage: 'Approval denied',
          ).toJson()),
          headers: {'Content-Type': 'application/json'},
        );
      }
    }

    session.status = RemoteDesktopSessionStatus.negotiating;
    notifyListeners();

    // Watchdog: если viewer не успел открыть WS / упал — не блокируем хост
    // навсегда. Через 20с зависшая сессия будет автоматически закрыта.
    session.wsConnectWatchdog =
        Timer(const Duration(seconds: 20), () async {
      if (_sessions[sessionId] != null && session.ws == null) {
        AppLogger.log(
            'RD host: watchdog dropping session $sessionId — viewer never connected WS');
        await _terminate(session, RemoteDesktopSessionStatus.failed,
            error: 'Viewer did not open WebSocket within 20 seconds');
      }
    });

    return shelf.Response.ok(
      jsonEncode(RemoteDesktopRequestResponse(
        status: RemoteDesktopRequestStatus.accepted,
        sessionId: sessionId,
        sessionToken: sessionToken,
        wsPath: '/api/rd/ws',
        grantsControl: session.grantsControl,
        grantsAudio: session.grantsAudio,
      ).toJson()),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// REST endpoint POST /api/rd/end?sessionId=..&token=..
  Future<shelf.Response> handleEnd(shelf.Request request) async {
    final id = request.url.queryParameters['sessionId'];
    final token = request.url.queryParameters['token'];
    if (id == null || token == null) {
      return shelf.Response.badRequest(body: 'missing params');
    }
    final session = _sessions[id];
    if (session == null || session.sessionToken != token) {
      return shelf.Response.notFound('session not found');
    }
    await _terminate(session, RemoteDesktopSessionStatus.closed);
    return shelf.Response.ok(jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'});
  }

  /// WebSocket signaling channel (handler для shelf_web_socket.webSocketHandler).
  shelf.Handler get webSocketSignalingHandler {
    return webSocketHandler((WebSocketChannel ws, dynamic _) {
      _onWsConnected(ws);
    });
  }

  void _onWsConnected(WebSocketChannel ws) {
    // Авторизация: первое сообщение должно быть hello с sessionId+token.
    StreamSubscription? sub;
    _HostSession? session;

    sub = ws.stream.listen(
      (data) async {
        try {
          final raw = data is String ? data : utf8.decode(data as List<int>);
          final json = jsonDecode(raw) as Map<String, dynamic>;
          if (session == null) {
            final sid = json['sessionId'] as String?;
            final tok = json['token'] as String?;
            final found = sid != null ? _sessions[sid] : null;
            if (found == null || found.sessionToken != tok) {
              ws.sink.add(jsonEncode({
                'type': RemoteDesktopSignalType.error.name,
                'payload': {'message': 'invalid session'},
              }));
              await ws.sink.close();
              return;
            }
            session = found;
            session!.ws = ws;
            session!.wsConnectWatchdog?.cancel();
            session!.wsConnectWatchdog = null;
            await _startHostMedia(session!);
            return;
          }

          final signal = RemoteDesktopSignal.fromJson(json);
          try {
            await _handleHostSignal(session!, signal);
          } catch (e, st) {
            AppLogger.log(
                'RD host: handler for ${signal.type.name} failed: $e\n$st');
            await _failSession(session!,
                'Ошибка обработки сигнала ${signal.type.name} на хосте:\n$e',
                st);
          }
        } catch (e, st) {
          AppLogger.log('RD host WS parse error: $e\n$st');
        }
      },
      onDone: () async {
        sub?.cancel();
        if (session != null) {
          await _terminate(session!, RemoteDesktopSessionStatus.closed);
        }
      },
      onError: (e) async {
        sub?.cancel();
        if (session != null) {
          await _terminate(session!, RemoteDesktopSessionStatus.failed,
              error: e.toString());
        }
      },
      cancelOnError: false,
    );
  }

  Future<void> _startHostMedia(_HostSession session) async {
    try {
      AppLogger.log(
          'RD host: starting media for session ${session.sessionId} '
          '(audio=${session.grantsAudio}, fps=${_settings.defaultFps})');

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
      session.pc = pc;

      // На Windows/Linux/macOS flutter_webrtc требует, чтобы источник
      // экрана был получен через desktopCapturer.getSources() и его deviceId
      // явно передавался в getDisplayMedia. Без этого нативная часть падает с
      // "Unable to getDisplayMedia: source not found!".
      MediaStream stream;
      try {
        stream = await _captureScreenStream(session);
      } catch (e, st) {
        AppLogger.log('RD host: screen capture failed: $e\n$st');
        await _failSession(
            session,
            'Не удалось захватить экран хоста: $e',
            st);
        return;
      }

      final videoTracks = stream.getVideoTracks();
      if (videoTracks.isEmpty) {
        AppLogger.log('RD host: getDisplayMedia returned no video tracks');
        await _failSession(session,
            'Захват экрана не вернул видео-треков. '
            'Проверь, что выбран источник в системном окне выбора экрана.');
        try {
          await stream.dispose();
        } catch (_) {}
        return;
      }
      session.screenStream = stream;
      AppLogger.log(
          'RD host: captured ${videoTracks.length} video track(s), '
          '${stream.getAudioTracks().length} audio track(s)');

      for (final track in videoTracks) {
        await pc.addTrack(track, stream);
      }
      for (final track in stream.getAudioTracks()) {
        await pc.addTrack(track, stream);
      }

      pc.onIceCandidate = (RTCIceCandidate candidate) {
        session.ws?.sink.add(jsonEncode(RemoteDesktopSignal(
          type: RemoteDesktopSignalType.iceCandidate,
          payload: {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        ).toJson()));
      };

      pc.onConnectionState = (state) {
        AppLogger.log(
            'RD host: peer connection state for ${session.sessionId} = $state');
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          session.status = RemoteDesktopSessionStatus.streaming;
          notifyListeners();
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          _failSession(session,
              'WebRTC peer connection failed (ICE/firewall problem).');
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          _terminate(session, RemoteDesktopSessionStatus.closed);
        }
      };

      pc.onIceConnectionState = (state) {
        AppLogger.log(
            'RD host: ICE connection state for ${session.sessionId} = $state');
        if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          _failSession(session,
              'ICE connection failed. Скорее всего разные подсети или фаервол '
              'блокирует UDP. Попробуй настроить TURN-сервер.');
        }
      };

      pc.onDataChannel = (RTCDataChannel channel) {
        if (channel.label == 'scn-rd-input') {
          session.inputChannel = channel;
          channel.onMessage = (msg) {
            if (!msg.isBinary) {
              _onInputEvent(session, msg.text);
            }
          };
        }
      };

      // Применяем bitrate cap ко всем video sender'ам.
      if (_settings.defaultVideoBitrateKbps > 0) {
        for (final sender in await pc.getSenders()) {
          if (sender.track?.kind == 'video') {
            final params = sender.parameters;
            params.encodings ??= [];
            if (params.encodings!.isEmpty) {
              params.encodings!.add(RTCRtpEncoding(
                  maxBitrate: _settings.defaultVideoBitrateKbps * 1000));
            } else {
              for (final enc in params.encodings!) {
                enc.maxBitrate = _settings.defaultVideoBitrateKbps * 1000;
              }
            }
            await sender.setParameters(params);
          }
        }
      }

      AppLogger.log('RD host: sending hostReady to ${session.sessionId}');
      session.ws?.sink.add(jsonEncode(RemoteDesktopSignal(
        type: RemoteDesktopSignalType.hostReady,
        payload: {
          'audioEnabled': session.grantsAudio,
          'controlAllowed': session.grantsControl,
          'preferredCodec': _settings.preferredVideoCodec,
        },
      ).toJson()));

      _startStatsTimer(session);
    } catch (e, st) {
      AppLogger.log('Failed to start RD host media: $e\n$st');
      await _failSession(
          session,
          'Внутренняя ошибка при запуске стриминга экрана: $e',
          st);
    }
  }

  /// Захватывает экран хоста.
  ///
  /// flutter_webrtc на Windows/Linux/macOS требует, чтобы источник экрана
  /// сначала был получен через [desktopCapturer.getSources], а его id
  /// передавался в [getDisplayMedia] в виде `chromeMediaSource` /
  /// `sourceId`. Вызов `getDisplayMedia({'video': true})` напрямую падает с
  /// `Unable to getDisplayMedia: source not found!`.
  Future<MediaStream> _captureScreenStream(_HostSession session) async {
    final fps = _settings.defaultFps > 0 ? _settings.defaultFps : 30;
    AppLogger.log('RD host: enumerating desktop sources (fps=$fps)…');

    List<DesktopCapturerSource> sources;
    try {
      sources = await desktopCapturer
          .getSources(types: [SourceType.Screen]);
    } catch (e, st) {
      AppLogger.log('RD host: desktopCapturer.getSources failed: $e\n$st');
      rethrow;
    }
    AppLogger.log(
        'RD host: desktop sources: ${sources.map((s) => '${s.id}:${s.name}').join(', ')}');

    if (sources.isEmpty) {
      throw StateError(
          'desktopCapturer вернул 0 источников Screen. '
          'Проверь, что приложение запущено на машине с дисплеем '
          '(не в headless RDP-сессии без активного входа).');
    }
    final source = sources.first;

    // Сначала пробуем нативный Windows/Linux/macOS путь через chromeMediaSource.
    final Map<String, dynamic> nativeConstraints = {
      'audio': false,
      'video': {
        'mandatory': {
          'chromeMediaSource': 'desktop',
          'chromeMediaSourceId': source.id,
          'maxFrameRate': fps,
          'minFrameRate': fps,
        },
        'optional': const <Map<String, dynamic>>[],
      },
    };
    try {
      AppLogger.log(
          'RD host: getDisplayMedia (native) sourceId=${source.id}…');
      final stream =
          await navigator.mediaDevices.getDisplayMedia(nativeConstraints);
      if (stream.getVideoTracks().isNotEmpty) return stream;
      AppLogger.log(
          'RD host: native getDisplayMedia returned 0 video tracks, trying fallback');
      try {
        await stream.dispose();
      } catch (_) {}
    } catch (e, st) {
      AppLogger.log(
          'RD host: native getDisplayMedia failed: $e\n$st — trying fallback');
    }

    // Fallback: deviceId.exact (web-style) — иногда срабатывает на новых
    // версиях flutter_webrtc.
    final Map<String, dynamic> fallbackConstraints = {
      'audio': false,
      'video': {
        'deviceId': {'exact': source.id},
        'mandatory': {
          'maxFrameRate': fps,
          'minFrameRate': fps,
        },
      },
    };
    AppLogger.log(
        'RD host: getDisplayMedia (deviceId.exact) sourceId=${source.id}…');
    final stream =
        await navigator.mediaDevices.getDisplayMedia(fallbackConstraints);
    if (stream.getVideoTracks().isEmpty) {
      try {
        await stream.dispose();
      } catch (_) {}
      throw StateError(
          'getDisplayMedia вернул поток без видео-треков для источника '
          '${source.id} (${source.name}).');
    }
    return stream;
  }

  /// Аварийное завершение сессии: отправляет error-сигнал клиенту с
  /// человекочитаемым сообщением (и stack trace, если есть), и только потом
  /// закрывает peer/ws.
  Future<void> _failSession(_HostSession session, String message,
      [StackTrace? stackTrace]) async {
    final fullMessage = stackTrace == null
        ? message
        : '$message\n\nStack:\n$stackTrace';
    AppLogger.log('RD host: failing session ${session.sessionId}: $message'
        '${stackTrace != null ? '\n$stackTrace' : ''}');
    try {
      session.ws?.sink.add(jsonEncode({
        'type': RemoteDesktopSignalType.error.name,
        'payload': {'message': fullMessage},
      }));
    } catch (_) {}
    await _terminate(session, RemoteDesktopSessionStatus.failed,
        error: fullMessage);
  }

  Future<void> _handleHostSignal(
      _HostSession session, RemoteDesktopSignal signal) async {
    switch (signal.type) {
      case RemoteDesktopSignalType.offer:
        final pc = session.pc;
        if (pc == null) return;
        await pc.setRemoteDescription(RTCSessionDescription(
          signal.payload['sdp'] as String?,
          signal.payload['type'] as String?,
        ));
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        session.ws?.sink.add(jsonEncode(RemoteDesktopSignal(
          type: RemoteDesktopSignalType.answer,
          payload: {
            'sdp': answer.sdp,
            'type': answer.type,
          },
        ).toJson()));
        break;
      case RemoteDesktopSignalType.iceCandidate:
        final pc = session.pc;
        if (pc == null) return;
        await pc.addCandidate(RTCIceCandidate(
          signal.payload['candidate'] as String?,
          signal.payload['sdpMid'] as String?,
          signal.payload['sdpMLineIndex'] as int?,
        ));
        break;
      case RemoteDesktopSignalType.bye:
        await _terminate(session, RemoteDesktopSessionStatus.closed);
        break;
      case RemoteDesktopSignalType.ping:
        session.ws?.sink.add(jsonEncode(
            const RemoteDesktopSignal(type: RemoteDesktopSignalType.pong)
                .toJson()));
        break;
      case RemoteDesktopSignalType.qualityChange:
        await _applyQualityChange(session, signal.payload);
        break;
      default:
        break;
    }
  }

  void _onInputEvent(_HostSession session, String jsonText) {
    if (!session.grantsControl) return;
    if (!_inputInjector.isAvailable) return;
    try {
      final json = jsonDecode(jsonText) as Map<String, dynamic>;
      final event = RemoteInputEvent.fromJson(json);
      _trackHeldInput(session, event);
      _inputInjector.inject(event);
    } catch (e) {
      AppLogger.log('RD input parse error: $e');
    }
  }

  /// Запоминает удерживаемые мышью кнопки и нажатые клавиши, чтобы при
  /// разрыве сессии можно было их корректно отжать (иначе на удалённой
  /// машине останется залипшая клавиша/кнопка).
  void _trackHeldInput(_HostSession session, RemoteInputEvent event) {
    switch (event.kind) {
      case RemoteInputEventKind.mouseDown:
        if (event.button != null) session.heldMouseButtons.add(event.button!);
        break;
      case RemoteInputEventKind.mouseUp:
        if (event.button != null) session.heldMouseButtons.remove(event.button!);
        break;
      case RemoteInputEventKind.keyDown:
        if (event.keyCode != null) session.heldKeys.add(event.keyCode!);
        break;
      case RemoteInputEventKind.keyUp:
        if (event.keyCode != null) session.heldKeys.remove(event.keyCode!);
        break;
      default:
        break;
    }
  }

  /// Аварийно отжимает всё, что удерживалось viewer'ом, чтобы на хосте не
  /// зависла клавиша/кнопка после внезапного дисконнекта.
  void _releaseAllHeldInput(_HostSession session) {
    if (!_inputInjector.isAvailable) return;
    final ts = DateTime.now().microsecondsSinceEpoch;
    for (final btn in session.heldMouseButtons.toList()) {
      try {
        _inputInjector.inject(RemoteInputEvent(
          kind: RemoteInputEventKind.mouseUp,
          button: btn,
          timestampUs: ts,
        ));
      } catch (_) {}
    }
    session.heldMouseButtons.clear();
    for (final code in session.heldKeys.toList()) {
      try {
        _inputInjector.inject(RemoteInputEvent(
          kind: RemoteInputEventKind.keyUp,
          keyCode: code,
          timestampUs: ts,
        ));
      } catch (_) {}
    }
    session.heldKeys.clear();
  }

  Future<void> _applyQualityChange(
      _HostSession session, Map<String, dynamic> payload) async {
    final pc = session.pc;
    if (pc == null) return;
    final bitrateKbps = payload['bitrateKbps'] as int?;
    final maxFps = payload['fps'] as int?;
    for (final sender in await pc.getSenders()) {
      if (sender.track?.kind != 'video') continue;
      final params = sender.parameters;
      params.encodings ??= [RTCRtpEncoding()];
      for (final enc in params.encodings!) {
        if (bitrateKbps != null && bitrateKbps > 0) {
          enc.maxBitrate = bitrateKbps * 1000;
        }
        if (maxFps != null && maxFps > 0) {
          enc.maxFramerate = maxFps;
        }
      }
      await sender.setParameters(params);
    }
  }

  void _startStatsTimer(_HostSession session) {
    session.statsTimer?.cancel();
    session.statsTimer =
        Timer.periodic(const Duration(seconds: 2), (_) async {
      final pc = session.pc;
      if (pc == null) return;
      try {
        final stats = await pc.getStats();
        double videoKbps = 0;
        double audioKbps = 0;
        double fps = 0;
        int packetsLost = 0;
        double prevPacketsLost = 0;
        int rtt = 0;
        int width = 0;
        int height = 0;
        double currentBytesSent = 0;
        for (final report in stats) {
          final values = report.values;
          if (report.type == 'outbound-rtp') {
            final kind = values['kind'] ?? values['mediaType'];
            final bytesSent = (values['bytesSent'] as num?)?.toDouble() ?? 0;
            if (kind == 'video') {
              currentBytesSent += bytesSent;
              fps = (values['framesPerSecond'] as num?)?.toDouble() ?? fps;
              width = (values['frameWidth'] as num?)?.toInt() ?? width;
              height = (values['frameHeight'] as num?)?.toInt() ?? height;
            } else if (kind == 'audio') {
              currentBytesSent += bytesSent;
            }
          } else if (report.type == 'remote-inbound-rtp') {
            packetsLost +=
                (values['packetsLost'] as num?)?.toInt() ?? 0;
            rtt = (((values['roundTripTime'] as num?)?.toDouble() ?? 0) *
                    1000)
                .toInt();
          }
        }

        // Дельта по байтам с прошлого тика для аккуратной оценки kbps.
        if (session.lastBytesSent > 0) {
          final deltaBytes = currentBytesSent - session.lastBytesSent;
          final kbps = (deltaBytes > 0 ? deltaBytes : 0) * 8 / 1000 / 2;
          videoKbps = kbps; // в основном видео доминирует
        }
        session.lastBytesSent = currentBytesSent;

        session.lastStats = RemoteDesktopStats(
          videoBitrateKbps: videoKbps,
          audioBitrateKbps: audioKbps,
          framesPerSecond: fps,
          packetsLost: packetsLost,
          roundTripTimeMs: rtt,
          frameWidth: width,
          frameHeight: height,
          updatedAt: DateTime.now(),
        );

        // Адаптивный bitrate (только если в настройках стоит auto, т.е.
        // пользователь не зафиксировал жёсткое значение).
        if (_settings.defaultVideoBitrateKbps == 0) {
          await _adaptBitrate(session,
              packetsLost: packetsLost, rttMs: rtt, fps: fps);
        }

        // Сообщаем viewer'у статистику и текущий потолок.
        try {
          session.ws?.sink.add(jsonEncode(RemoteDesktopSignal(
            type: RemoteDesktopSignalType.stats,
            payload: {
              'videoKbps': videoKbps,
              'audioKbps': audioKbps,
              'fps': fps,
              'rtt': rtt,
              'lost': packetsLost,
              'width': width,
              'height': height,
              'maxKbps': session.currentMaxBitrateKbps,
            },
          ).toJson()));
        } catch (_) {}

        notifyListeners();
        prevPacketsLost = packetsLost.toDouble(); // (зарезервировано)
        // ignore: unused_local_variable
        prevPacketsLost;
      } catch (_) {
        // ignore stats errors
      }
    });
  }

  /// Простая AIMD-подобная адаптация.
  /// При packetsLost растёт быстро или RTT > 250ms — уменьшаем потолок на 25%.
  /// Иначе — раз в несколько тиков плавно увеличиваем на 10% до 25 Mbps.
  Future<void> _adaptBitrate(
    _HostSession session, {
    required int packetsLost,
    required int rttMs,
    required double fps,
  }) async {
    const minKbps = 500;
    const maxKbps = 25000;
    int current = session.currentMaxBitrateKbps;
    if (current <= 0) {
      current = 4000; // стартовое значение
    }

    final stats = session.lastStats;
    int prevLost = 0;
    if (stats != null) {
      prevLost = stats.packetsLost;
    }
    final lossDelta = packetsLost - prevLost;

    int next = current;
    if (rttMs > 250 || lossDelta > 50 || (fps > 0 && fps < 5)) {
      next = (current * 0.75).round();
    } else if (rttMs > 0 && rttMs < 120 && lossDelta < 5) {
      next = (current * 1.10).round();
    }
    next = next.clamp(minKbps, maxKbps);
    if (next != current) {
      session.currentMaxBitrateKbps = next;
      await _applyMaxBitrate(session, next);
    } else if (current > 0) {
      session.currentMaxBitrateKbps = current;
    }
  }

  Future<void> _applyMaxBitrate(_HostSession session, int kbps) async {
    final pc = session.pc;
    if (pc == null) return;
    for (final sender in await pc.getSenders()) {
      if (sender.track?.kind != 'video') continue;
      final params = sender.parameters;
      params.encodings ??= [RTCRtpEncoding()];
      for (final enc in params.encodings!) {
        enc.maxBitrate = kbps * 1000;
      }
      await sender.setParameters(params);
    }
  }

  /// Подтверждение / отклонение сессии из UI.
  void respondToApproval(String sessionId, bool approved) {
    final session = _sessions[sessionId];
    final completer = session?.approvalCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(approved);
    }
  }

  /// Прерывание сессии вручную.
  Future<void> kickSession(String sessionId) async {
    final session = _sessions[sessionId];
    if (session != null) {
      await _terminate(session, RemoteDesktopSessionStatus.closed);
    }
  }

  Future<void> _terminate(_HostSession session,
      RemoteDesktopSessionStatus status,
      {String? error}) async {
    if (!_sessions.containsKey(session.sessionId)) return;
    session.status = status;
    session.errorMessage = error;
    session.statsTimer?.cancel();
    session.wsConnectWatchdog?.cancel();
    session.wsConnectWatchdog = null;
    // Безопасность: viewer мог упасть, удерживая кнопку/клавишу. Без явного
    // release они "залипнут" на хосте.
    _releaseAllHeldInput(session);
    try {
      session.ws?.sink.add(jsonEncode(RemoteDesktopSignal(
        type: RemoteDesktopSignalType.bye,
        payload: {
          'status': status.name,
          if (error != null) 'reason': error,
        },
      ).toJson()));
    } catch (_) {}
    try {
      await session.ws?.sink.close();
    } catch (_) {}
    try {
      for (final track in session.screenStream?.getTracks() ?? []) {
        await track.stop();
      }
      await session.screenStream?.dispose();
    } catch (_) {}
    try {
      await session.inputChannel?.close();
    } catch (_) {}
    try {
      await session.pc?.close();
    } catch (_) {}
    _sessions.remove(session.sessionId);
    notifyListeners();
  }

  Future<void> shutdown() async {
    final ids = _sessions.keys.toList();
    for (final id in ids) {
      await kickSession(id);
    }
  }

  String _peerAddressFromRequest(shelf.Request request) {
    final connInfo = request.context['shelf.io.connection_info'];
    if (connInfo is HttpConnectionInfo) {
      return connInfo.remoteAddress.address;
    }
    return request.headers['x-forwarded-for'] ??
        request.headers['remote-addr'] ??
        'unknown';
  }

  String _generateId() {
    final bytes =
        List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  @override
  void dispose() {
    _approvalController.close();
    _inputInjector.dispose();
    shutdown();
    super.dispose();
  }
}
