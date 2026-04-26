import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:scn/models/remote_desktop_models.dart';
import 'package:scn/services/remote_desktop/remote_desktop_client_service.dart';
import 'package:scn/utils/logger.dart';

/// Полноэкранная страница для просмотра удалённого экрана.
///
/// Логика lifecycle: если на момент открытия уже есть активный
/// [RemoteDesktopClientService.active] — просто переиспользуем его (это
/// возврат пользователя в существующую сессию через "Continue"). Если нет —
/// создаём новый. При back-button КЛИЕНТА НЕ диспозим: сессия остаётся
/// активной и доступной из главной страницы. Полное закрытие — только через
/// явную кнопку "Disconnect".
class RemoteDesktopViewerPage extends StatefulWidget {
  final RemoteDesktopConnectParams params;

  const RemoteDesktopViewerPage({super.key, required this.params});

  @override
  State<RemoteDesktopViewerPage> createState() =>
      _RemoteDesktopViewerPageState();
}

class _RemoteDesktopViewerPageState extends State<RemoteDesktopViewerPage> {
  late final RemoteDesktopClientService _client;
  late final bool
      _ownsClient; // true если мы создали клиент сами; false если переиспользуем активный
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _videoKey = GlobalKey();
  StreamSubscription? _errorSub;
  bool _connecting = true;
  String? _error;
  bool _showStats = false;
  bool _controlActive = false; // переключатель view-only/control
  bool _captureKeyboard = true;
  Offset? _lastSentMove;
  int _lastMoveSentAtMs = 0;

  /// Битмаска кнопок мыши, которые сейчас удержаны (kPrimaryMouseButton и т.п.).
  /// Нужно для корректного mouseUp: PointerUpEvent.buttons всегда 0,
  /// поэтому без явного трекинга мы не знаем, какую именно кнопку отпускать.
  int _pressedMouseButtons = 0;
  bool _disconnecting = false;

  @override
  void initState() {
    super.initState();
    final existing = RemoteDesktopClientService.active;
    final canReuse = existing != null &&
        existing.session != null &&
        existing.session!.status != RemoteDesktopSessionStatus.closed &&
        existing.session!.status != RemoteDesktopSessionStatus.failed;
    if (canReuse) {
      _client = existing;
      _ownsClient = false;
      _connecting = false;
      _controlActive =
          _client.session?.inputMode == RemoteDesktopInputMode.full;
    } else {
      _client = RemoteDesktopClientService();
      _ownsClient = true;
    }
    _client.addListener(_onClientChange);
    _errorSub = _client.errors.listen((msg) {
      if (!mounted) return;
      setState(() {
        _error = _error == null ? msg : '$_error\n\n$msg';
        _connecting = false;
      });
    });
    if (_ownsClient) {
      _connect();
    }
  }

  Future<void> _connect() async {
    final ok = await _client.connect(widget.params);
    if (!mounted) return;
    setState(() {
      _connecting = false;
      if (!ok && _error == null) {
        _error = 'Failed to connect';
      }
      _controlActive =
          _client.session?.inputMode == RemoteDesktopInputMode.full;
    });
    if (_controlActive) {
      _focusNode.requestFocus();
    }
  }

  void _onClientChange() {
    if (!mounted) return;
    final canControl =
        _client.session?.inputMode == RemoteDesktopInputMode.full;
    if (canControl && _controlActive && !_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
    setState(() {});
  }

  /// Полное завершение сессии — вызывается ТОЛЬКО по явному кнопке
  /// "Disconnect". Отжимает удержанные клавиши/кнопки и закрывает WS.
  /// После этого `RemoteDesktopClientService.active` становится null.
  Future<void> _gracefulShutdown() async {
    if (_disconnecting) return;
    _disconnecting = true;
    AppLogger.log('RD viewer: gracefulShutdown begin');
    _releaseAllInput();
    try {
      await _client.disconnect();
    } catch (e) {
      AppLogger.log('RD viewer: disconnect threw: $e');
    }
    AppLogger.log('RD viewer: gracefulShutdown end');
  }

  /// Уход со страницы без закрытия сессии (back-button). Сессия остаётся
  /// в `RemoteDesktopClientService.active`, на главной странице появится
  /// блок "Active outgoing session" с кнопкой Continue.
  void _detachFromClient() {
    _errorSub?.cancel();
    _errorSub = null;
    _client.removeListener(_onClientChange);
    // Отжимаем то, что было нажато на момент back, чтобы курсор/клавиша не
    // залипли на хосте.
    _releaseAllInput();
  }

  @override
  void dispose() {
    AppLogger.log(
        'RD viewer: dispose, ownsClient=$_ownsClient disconnecting=$_disconnecting');
    _errorSub?.cancel();
    _focusNode.dispose();
    _client.removeListener(_onClientChange);
    _releaseAllInput();
    if (_disconnecting) {
      _client.dispose();
    }
    // Иначе — клиент остаётся живым в `RemoteDesktopClientService.active`,
    // его освободит либо явный disconnect, либо повторный заход на страницу.
    super.dispose();
  }

  /// Отправить mouseUp/keyUp для всего, что сейчас нажато. Вызывать перед
  /// закрытием страницы, переключением controlActive в false, потерей фокуса
  /// и т.п. — иначе мышь/клавиша "залипнет" на удалённой машине.
  void _releaseAllInput() {
    if (_pressedMouseButtons != 0) {
      const buttonBits = [
        kPrimaryMouseButton,
        kSecondaryMouseButton,
        kMiddleMouseButton,
        kBackMouseButton,
        kForwardMouseButton,
      ];
      for (final b in buttonBits) {
        if ((_pressedMouseButtons & b) != 0) {
          _client.sendInputEvent(RemoteInputEvent(
            kind: RemoteInputEventKind.mouseUp,
            button: _mapButton(b),
            timestampUs: DateTime.now().microsecondsSinceEpoch,
          ));
        }
      }
      _pressedMouseButtons = 0;
    }
  }

  // ---------- input forwarding ----------

  Offset? _normalize(Offset local) {
    final renderBox =
        _videoKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return null;
    final size = renderBox.size;
    if (size.width == 0 || size.height == 0) return null;

    // RTCVideoView рисует поток с objectFit=contain. Если соотношение сторон
    // viewer-окна не совпадает с удаленным экраном, появляются черные поля.
    // Координаты мыши должны считаться только по реальному прямоугольнику
    // видео, иначе клик визуально уезжает вверх/вбок и не попадает в кнопки
    // свернуть/закрыть у окон на удаленной машине.
    final videoW = _client.videoRenderer.videoWidth > 0
        ? _client.videoRenderer.videoWidth
        : (_client.session?.stats?.frameWidth ?? 0);
    final videoH = _client.videoRenderer.videoHeight > 0
        ? _client.videoRenderer.videoHeight
        : (_client.session?.stats?.frameHeight ?? 0);

    var contentLeft = 0.0;
    var contentTop = 0.0;
    var contentWidth = size.width;
    var contentHeight = size.height;
    if (videoW > 0 && videoH > 0) {
      final boxAspect = size.width / size.height;
      final videoAspect = videoW / videoH;
      if (boxAspect > videoAspect) {
        contentHeight = size.height;
        contentWidth = contentHeight * videoAspect;
        contentLeft = (size.width - contentWidth) / 2;
      } else {
        contentWidth = size.width;
        contentHeight = contentWidth / videoAspect;
        contentTop = (size.height - contentHeight) / 2;
      }
    }

    final x = local.dx - contentLeft;
    final y = local.dy - contentTop;
    if (x < 0 || y < 0 || x > contentWidth || y > contentHeight) {
      return null;
    }
    final dx = (x / contentWidth).clamp(0.0, 1.0);
    final dy = (y / contentHeight).clamp(0.0, 1.0);
    return Offset(dx, dy);
  }

  void _sendMove(Offset local) {
    if (!_controlActive) return;
    final n = _normalize(local);
    if (n == null) return;
    // Жёсткий throttle по времени: не чаще 60 событий/сек. Без этого онHover
    // / onPointerMove на быстрой мыши бомбят DataChannel сотнями событий в
    // секунду, channel.send() начинает блокировать UI thread, и Flutter
    // успевает пропустить onPointerUp — Windows не отпускает mouse capture
    // окна, и курсор "залипает" внутри viewer'а. Симптом: всё видно, но
    // мышь перестала реагировать на машине viewer.
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastMoveSentAtMs < 16) return;
    if (_lastSentMove != null) {
      if ((n.dx - _lastSentMove!.dx).abs() < 0.001 &&
          (n.dy - _lastSentMove!.dy).abs() < 0.001) {
        return;
      }
    }
    _lastSentMove = n;
    _lastMoveSentAtMs = nowMs;
    _client.sendInputEvent(RemoteInputEvent(
      kind: RemoteInputEventKind.mouseMove,
      x: n.dx,
      y: n.dy,
      timestampUs: DateTime.now().microsecondsSinceEpoch,
    ));
  }

  void _sendButton(PointerDownEvent ev) {
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
    AppLogger.log(
        'RD viewer: PointerDown buttons=${ev.buttons} held=$_pressedMouseButtons '
        'controlActive=$_controlActive');
    if (!_controlActive) return;
    final n = _normalize(ev.localPosition);
    if (n == null) {
      return;
    }
    // Отправляем mouseDown ТОЛЬКО для тех кнопок, которые именно сейчас стали
    // нажатыми (новые в маске). Потом запоминаем актуальную маску.
    final newlyPressed = ev.buttons & ~_pressedMouseButtons;
    _pressedMouseButtons = ev.buttons;
    if (newlyPressed == 0) return;
    final ts = DateTime.now().microsecondsSinceEpoch;
    for (final b in const [
      kPrimaryMouseButton,
      kSecondaryMouseButton,
      kMiddleMouseButton,
      kBackMouseButton,
      kForwardMouseButton,
    ]) {
      if ((newlyPressed & b) != 0) {
        _client.sendInputEvent(RemoteInputEvent(
          kind: RemoteInputEventKind.mouseDown,
          x: n?.dx,
          y: n?.dy,
          button: _mapButton(b),
          timestampUs: ts,
        ));
      }
    }
  }

  void _sendButtonUp(PointerUpEvent ev) {
    AppLogger.log(
        'RD viewer: PointerUp buttons=${ev.buttons} held=$_pressedMouseButtons '
        'controlActive=$_controlActive');
    if (!_controlActive) return;
    // PointerUpEvent.buttons после Up почти всегда 0; считаем "разницу" —
    // именно те битовые позиции, которые ушли из удерживаемых, и отжимаем их.
    final released = _pressedMouseButtons & ~ev.buttons;
    _pressedMouseButtons = ev.buttons;
    if (released == 0) return;
    final n = _normalize(ev.localPosition);
    final ts = DateTime.now().microsecondsSinceEpoch;
    for (final b in const [
      kPrimaryMouseButton,
      kSecondaryMouseButton,
      kMiddleMouseButton,
      kBackMouseButton,
      kForwardMouseButton,
    ]) {
      if ((released & b) != 0) {
        _client.sendInputEvent(RemoteInputEvent(
          kind: RemoteInputEventKind.mouseUp,
          x: n?.dx,
          y: n?.dy,
          button: _mapButton(b),
          timestampUs: ts,
        ));
      }
    }
  }

  /// PointerCancelEvent: фокус ушёл со страницы / pointer уехал за окно.
  /// Отжимаем всё, чтобы не было залипших кнопок на удалённой машине.
  void _sendButtonCancel(PointerCancelEvent ev) {
    AppLogger.log(
        'RD viewer: PointerCancel buttons=${ev.buttons} held=$_pressedMouseButtons');
    if (_pressedMouseButtons == 0) return;
    _releaseAllInput();
  }

  void _sendScroll(PointerSignalEvent ev) {
    if (!_controlActive) return;
    if (ev is! PointerScrollEvent) return;
    _client.sendInputEvent(RemoteInputEvent(
      kind: RemoteInputEventKind.mouseScroll,
      scrollDeltaX: -ev.scrollDelta.dx,
      scrollDeltaY: -ev.scrollDelta.dy,
      timestampUs: DateTime.now().microsecondsSinceEpoch,
    ));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_controlActive || !_captureKeyboard) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final isDown = event is KeyDownEvent;
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final ctrl = pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight);
    final alt = pressed.contains(LogicalKeyboardKey.altLeft) ||
        pressed.contains(LogicalKeyboardKey.altRight);
    final meta = pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight);
    final text = event.character;
    if (isDown &&
        !ctrl &&
        !alt &&
        !meta &&
        text != null &&
        text.isNotEmpty &&
        !_isControlCharacter(text)) {
      _client.sendInputEvent(RemoteInputEvent(
        kind: RemoteInputEventKind.textInput,
        text: text,
        timestampUs: DateTime.now().microsecondsSinceEpoch,
      ));
      return KeyEventResult.handled;
    }
    _client.sendInputEvent(RemoteInputEvent(
      kind: isDown ? RemoteInputEventKind.keyDown : RemoteInputEventKind.keyUp,
      keyCode: event.logicalKey.keyId,
      physicalKeyCode: event.physicalKey.usbHidUsage,
      text: event.character,
      shift: pressed.contains(LogicalKeyboardKey.shiftLeft) ||
          pressed.contains(LogicalKeyboardKey.shiftRight),
      ctrl: ctrl,
      alt: alt,
      meta: meta,
      timestampUs: DateTime.now().microsecondsSinceEpoch,
    ));
    return KeyEventResult.handled;
  }

  bool _isControlCharacter(String value) {
    if (value.runes.length != 1) return false;
    final code = value.runes.first;
    return code < 0x20 || code == 0x7f;
  }

  RemoteMouseButton _mapButton(int btn) {
    if (btn == kSecondaryMouseButton) return RemoteMouseButton.right;
    if (btn == kMiddleMouseButton) return RemoteMouseButton.middle;
    if (btn == kBackMouseButton) return RemoteMouseButton.x1;
    if (btn == kForwardMouseButton) return RemoteMouseButton.x2;
    return RemoteMouseButton.left;
  }

  void _sendCtrlAltDel() {
    if (!_controlActive) return;
    final ts = DateTime.now().microsecondsSinceEpoch;
    final ctrl = LogicalKeyboardKey.controlLeft.keyId;
    final alt = LogicalKeyboardKey.altLeft.keyId;
    final del = LogicalKeyboardKey.delete.keyId;
    _client
      ..sendInputEvent(RemoteInputEvent(
          kind: RemoteInputEventKind.keyDown, keyCode: ctrl, timestampUs: ts))
      ..sendInputEvent(RemoteInputEvent(
          kind: RemoteInputEventKind.keyDown, keyCode: alt, timestampUs: ts))
      ..sendInputEvent(RemoteInputEvent(
          kind: RemoteInputEventKind.keyDown, keyCode: del, timestampUs: ts))
      ..sendInputEvent(RemoteInputEvent(
          kind: RemoteInputEventKind.keyUp, keyCode: del, timestampUs: ts))
      ..sendInputEvent(RemoteInputEvent(
          kind: RemoteInputEventKind.keyUp, keyCode: alt, timestampUs: ts))
      ..sendInputEvent(RemoteInputEvent(
          kind: RemoteInputEventKind.keyUp, keyCode: ctrl, timestampUs: ts));
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final session = _client.session;
    return PopScope(
      // На back просто отсоединяемся от клиент-сервиса (НЕ закрываем сессию).
      // Сессия остаётся живой в RemoteDesktopClientService.active, и юзер
      // может вернуться через "Continue" с главной страницы Remote Desktop.
      // Полное закрытие — только через явный кнопку Disconnect в toolbar.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _detachFromClient();
        if (mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black87,
          foregroundColor: Colors.white,
          title: Text('Remote: ${widget.params.host}',
              style: const TextStyle(fontSize: 14)),
          actions: _toolbarActions(session),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            _buildVideoArea(),
            if (_showStats && session?.stats != null)
              Positioned(
                left: 16,
                bottom: 16,
                child: _StatsPanel(stats: session!.stats!),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _toolbarActions(RemoteDesktopSession? session) {
    final allowed = session?.inputMode == RemoteDesktopInputMode.full;
    return [
      if (session != null) _buildStatusChip(session),
      Tooltip(
        message: allowed
            ? (_controlActive
                ? 'Disable input forwarding'
                : 'Enable input forwarding')
            : 'Host did not grant control',
        child: Switch.adaptive(
          value: _controlActive,
          onChanged: allowed
              ? (v) {
                  if (!v) _releaseAllInput();
                  setState(() => _controlActive = v);
                  if (v) _focusNode.requestFocus();
                }
              : null,
        ),
      ),
      if (_controlActive)
        IconButton(
          tooltip:
              _captureKeyboard ? 'Stop capturing keyboard' : 'Capture keyboard',
          icon: Icon(
              _captureKeyboard ? Icons.keyboard : Icons.keyboard_alt_outlined),
          onPressed: () => setState(() => _captureKeyboard = !_captureKeyboard),
        ),
      if (_controlActive)
        IconButton(
          tooltip: 'Send Ctrl + Alt + Del',
          icon: const Icon(Icons.warning_amber),
          onPressed: _sendCtrlAltDel,
        ),
      IconButton(
        tooltip: _showStats ? 'Hide stats' : 'Show stats',
        icon: Icon(_showStats ? Icons.bar_chart : Icons.bar_chart_outlined),
        onPressed: () => setState(() => _showStats = !_showStats),
      ),
      IconButton(
        tooltip: 'Disconnect',
        icon: const Icon(Icons.logout),
        onPressed: () async {
          await _gracefulShutdown();
          if (mounted) Navigator.of(context).maybePop();
        },
      ),
      const SizedBox(width: 8),
    ];
  }

  Widget _buildVideoArea() {
    if (_connecting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white70),
            SizedBox(height: 12),
            Text('Connecting...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
    }
    if (!_client.isVideoReady) {
      return const SizedBox.shrink();
    }

    final session = _client.session;
    final closedWithoutVideo = session != null &&
        (session.status == RemoteDesktopSessionStatus.closed ||
            session.status == RemoteDesktopSessionStatus.failed) &&
        _client.videoRenderer.srcObject == null;
    if (closedWithoutVideo) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.tv_off, size: 48, color: Colors.white54),
              const SizedBox(height: 12),
              Text(
                session.errorMessage ??
                    'Хост закрыл сессию до того, как пошёл видеопоток.\n'
                        'Проверь на хост-машине окно выбора экрана и логи.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
    }

    Widget videoView = RTCVideoView(
      _client.videoRenderer,
      key: _videoKey,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
    );

    if (_controlActive) {
      // ВАЖНО: используем ОДИН Listener для всех pointer events.
      // MouseRegion+Listener вместе создавали конкуренцию: onHover и
      // onPointerHover оба могли стрелять для одного движения, удваивая
      // нагрузку на DataChannel.
      videoView = MouseRegion(
        cursor: SystemMouseCursors.precise,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _sendButton,
          onPointerUp: _sendButtonUp,
          onPointerCancel: _sendButtonCancel,
          onPointerHover: (e) => _sendMove(e.localPosition),
          onPointerMove: (e) => _sendMove(e.localPosition),
          onPointerSignal: _sendScroll,
          child: videoView,
        ),
      );
    }

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: videoView,
    );
  }

  Widget _buildStatusChip(RemoteDesktopSession session) {
    Color color;
    String label;
    switch (session.status) {
      case RemoteDesktopSessionStatus.streaming:
        color = Colors.green;
        label = 'Live';
        break;
      case RemoteDesktopSessionStatus.negotiating:
        color = Colors.amber;
        label = 'Negotiating';
        break;
      case RemoteDesktopSessionStatus.pendingApproval:
        color = Colors.blueGrey;
        label = 'Waiting';
        break;
      case RemoteDesktopSessionStatus.failed:
        color = Colors.redAccent;
        label = 'Failed';
        break;
      case RemoteDesktopSessionStatus.rejected:
        color = Colors.redAccent;
        label = 'Rejected';
        break;
      case RemoteDesktopSessionStatus.closed:
        color = Colors.grey;
        label = 'Closed';
        break;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Chip(
        backgroundColor: color.withOpacity(0.2),
        side: BorderSide(color: color, width: 1),
        label: Text(label, style: TextStyle(color: color, fontSize: 12)),
      ),
    );
  }
}

class _StatsPanel extends StatelessWidget {
  final RemoteDesktopStats stats;
  const _StatsPanel({required this.stats});

  @override
  Widget build(BuildContext context) {
    final style = const TextStyle(color: Colors.white, fontSize: 12);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Video: ${stats.videoBitrateKbps.toStringAsFixed(0)} kbps',
              style: style),
          Text('Audio: ${stats.audioBitrateKbps.toStringAsFixed(0)} kbps',
              style: style),
          Text('FPS: ${stats.framesPerSecond.toStringAsFixed(1)}',
              style: style),
          Text('RTT: ${stats.roundTripTimeMs} ms', style: style),
          Text('Resolution: ${stats.frameWidth}x${stats.frameHeight}',
              style: style),
        ],
      ),
    );
  }
}
