import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:scn/models/remote_desktop_models.dart';
import 'package:scn/services/remote_desktop/remote_desktop_client_service.dart';

/// Полноэкранная страница для просмотра удалённого экрана.
class RemoteDesktopViewerPage extends StatefulWidget {
  final RemoteDesktopConnectParams params;

  const RemoteDesktopViewerPage({super.key, required this.params});

  @override
  State<RemoteDesktopViewerPage> createState() =>
      _RemoteDesktopViewerPageState();
}

class _RemoteDesktopViewerPageState extends State<RemoteDesktopViewerPage> {
  final RemoteDesktopClientService _client = RemoteDesktopClientService();
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _videoKey = GlobalKey();
  StreamSubscription? _errorSub;
  bool _connecting = true;
  String? _error;
  bool _showStats = false;
  bool _controlActive = false; // переключатель view-only/control
  bool _captureKeyboard = true;
  Offset? _lastSentMove;

  @override
  void initState() {
    super.initState();
    _client.addListener(_onClientChange);
    _errorSub = _client.errors.listen((msg) {
      if (!mounted) return;
      setState(() {
        // Накапливаем сообщения, чтобы пользователь видел всю историю
        // (например, сначала ICE failed, затем bye от хоста).
        _error = _error == null ? msg : '$_error\n\n$msg';
        _connecting = false;
      });
    });
    _connect();
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
  }

  void _onClientChange() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    _focusNode.dispose();
    _client.removeListener(_onClientChange);
    _client.dispose();
    super.dispose();
  }

  // ---------- input forwarding ----------

  Offset? _normalize(Offset local) {
    final renderBox = _videoKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return null;
    final size = renderBox.size;
    if (size.width == 0 || size.height == 0) return null;
    final dx = (local.dx / size.width).clamp(0.0, 1.0);
    final dy = (local.dy / size.height).clamp(0.0, 1.0);
    return Offset(dx, dy);
  }

  void _sendMove(Offset local) {
    if (!_controlActive) return;
    final n = _normalize(local);
    if (n == null) return;
    if (_lastSentMove != null) {
      // Throttling — игнорируем move с дельтой <0.001 от последнего.
      if ((n.dx - _lastSentMove!.dx).abs() < 0.001 &&
          (n.dy - _lastSentMove!.dy).abs() < 0.001) {
        return;
      }
    }
    _lastSentMove = n;
    _client.sendInputEvent(RemoteInputEvent(
      kind: RemoteInputEventKind.mouseMove,
      x: n.dx,
      y: n.dy,
      timestampUs: DateTime.now().microsecondsSinceEpoch,
    ));
  }

  void _sendButton(PointerDownEvent ev) {
    if (!_controlActive) return;
    final n = _normalize(ev.localPosition);
    _client.sendInputEvent(RemoteInputEvent(
      kind: RemoteInputEventKind.mouseDown,
      x: n?.dx,
      y: n?.dy,
      button: _mapButton(ev.buttons),
      timestampUs: DateTime.now().microsecondsSinceEpoch,
    ));
  }

  void _sendButtonUp(PointerUpEvent ev) {
    if (!_controlActive) return;
    final n = _normalize(ev.localPosition);
    _client.sendInputEvent(RemoteInputEvent(
      kind: RemoteInputEventKind.mouseUp,
      x: n?.dx,
      y: n?.dy,
      button: _mapButton(ev.buttons == 0 ? kPrimaryMouseButton : ev.buttons),
      timestampUs: DateTime.now().microsecondsSinceEpoch,
    ));
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
    _client.sendInputEvent(RemoteInputEvent(
      kind: isDown
          ? RemoteInputEventKind.keyDown
          : RemoteInputEventKind.keyUp,
      keyCode: event.logicalKey.keyId,
      physicalKeyCode: event.physicalKey.usbHidUsage,
      text: event.character,
      shift: pressed.contains(LogicalKeyboardKey.shiftLeft) ||
          pressed.contains(LogicalKeyboardKey.shiftRight),
      ctrl: pressed.contains(LogicalKeyboardKey.controlLeft) ||
          pressed.contains(LogicalKeyboardKey.controlRight),
      alt: pressed.contains(LogicalKeyboardKey.altLeft) ||
          pressed.contains(LogicalKeyboardKey.altRight),
      meta: pressed.contains(LogicalKeyboardKey.metaLeft) ||
          pressed.contains(LogicalKeyboardKey.metaRight),
      timestampUs: DateTime.now().microsecondsSinceEpoch,
    ));
    return KeyEventResult.handled;
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
          kind: RemoteInputEventKind.keyDown,
          keyCode: ctrl,
          timestampUs: ts))
      ..sendInputEvent(RemoteInputEvent(
          kind: RemoteInputEventKind.keyDown,
          keyCode: alt,
          timestampUs: ts))
      ..sendInputEvent(RemoteInputEvent(
          kind: RemoteInputEventKind.keyDown,
          keyCode: del,
          timestampUs: ts))
      ..sendInputEvent(RemoteInputEvent(
          kind: RemoteInputEventKind.keyUp,
          keyCode: del,
          timestampUs: ts))
      ..sendInputEvent(RemoteInputEvent(
          kind: RemoteInputEventKind.keyUp,
          keyCode: alt,
          timestampUs: ts))
      ..sendInputEvent(RemoteInputEvent(
          kind: RemoteInputEventKind.keyUp,
          keyCode: ctrl,
          timestampUs: ts));
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final session = _client.session;
    return Scaffold(
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
                  setState(() => _controlActive = v);
                  if (v) _focusNode.requestFocus();
                }
              : null,
        ),
      ),
      if (_controlActive)
        IconButton(
          tooltip: _captureKeyboard
              ? 'Stop capturing keyboard'
              : 'Capture keyboard',
          icon: Icon(_captureKeyboard ? Icons.keyboard : Icons.keyboard_alt_outlined),
          onPressed: () =>
              setState(() => _captureKeyboard = !_captureKeyboard),
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
          await _client.disconnect();
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
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
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
      videoView = MouseRegion(
        cursor: SystemMouseCursors.precise,
        onHover: (e) => _sendMove(e.localPosition),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _sendButton,
          onPointerUp: _sendButtonUp,
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
          Text('FPS: ${stats.framesPerSecond.toStringAsFixed(1)}', style: style),
          Text('RTT: ${stats.roundTripTimeMs} ms', style: style),
          Text('Resolution: ${stats.frameWidth}x${stats.frameHeight}',
              style: style),
        ],
      ),
    );
  }
}
