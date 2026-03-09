import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:scn/models/remote_peer.dart';
import 'package:scn/models/signaling_models.dart';
import 'package:scn/utils/logger.dart';

class WebRtcTransportService {
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  final Set<String> _candidateTypes = <String>{};

  void Function(Map<String, dynamic> payload)? onLocalOffer;
  void Function(Map<String, dynamic> payload)? onLocalAnswer;
  void Function(Map<String, dynamic> payload)? onLocalIceCandidate;
  void Function(PeerConnectionPath path)? onConnectionPathChanged;
  void Function(String state)? onConnectionStateChanged;
  void Function(String state)? onIceConnectionStateChanged;
  void Function(String state)? onDataChannelStateChanged;
  void Function(Map<String, dynamic> message)? onDataMessage;

  bool get isConnected =>
      _peerConnection?.connectionState ==
      RTCPeerConnectionState.RTCPeerConnectionStateConnected;

  Future<void> createHostConnection({
    required List<IceServerConfig> iceServers,
    bool preferRelay = false,
  }) async {
    await _createPeerConnection(
      iceServers: iceServers,
      preferRelay: preferRelay,
      createDataChannel: true,
    );

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    onLocalOffer?.call({
      'sdp': offer.sdp,
      'type': offer.type,
    });
  }

  Future<void> prepareJoinerConnection({
    required List<IceServerConfig> iceServers,
    bool preferRelay = false,
  }) async {
    await _createPeerConnection(
      iceServers: iceServers,
      preferRelay: preferRelay,
      createDataChannel: false,
    );
  }

  Future<void> handleOffer(Map<String, dynamic> offer) async {
    final connection = _peerConnection;
    if (connection == null) {
      throw StateError('Peer connection is not ready');
    }

    await connection.setRemoteDescription(
      RTCSessionDescription(
        offer['sdp'] as String?,
        offer['type'] as String?,
      ),
    );

    final answer = await connection.createAnswer();
    await connection.setLocalDescription(answer);
    onLocalAnswer?.call({
      'sdp': answer.sdp,
      'type': answer.type,
    });
  }

  Future<void> handleAnswer(Map<String, dynamic> answer) async {
    final connection = _peerConnection;
    if (connection == null) {
      throw StateError('Peer connection is not ready');
    }

    await connection.setRemoteDescription(
      RTCSessionDescription(
        answer['sdp'] as String?,
        answer['type'] as String?,
      ),
    );
  }

  Future<void> addRemoteCandidate(Map<String, dynamic> candidate) async {
    final connection = _peerConnection;
    if (connection == null) {
      throw StateError('Peer connection is not ready');
    }

    final rawCandidate = candidate['candidate'] as String?;
    if (rawCandidate != null) {
      _registerCandidate(rawCandidate);
    }

    await connection.addCandidate(
      RTCIceCandidate(
        rawCandidate,
        candidate['sdpMid'] as String?,
        candidate['sdpMLineIndex'] as int?,
      ),
    );
  }

  void sendJson(Map<String, dynamic> payload) {
    _dataChannel?.send(RTCDataChannelMessage(jsonEncode(payload)));
  }

  Future<void> close() async {
    await _dataChannel?.close();
    _dataChannel = null;
    await _peerConnection?.close();
    _peerConnection = null;
    _candidateTypes.clear();
  }

  Future<void> _createPeerConnection({
    required List<IceServerConfig> iceServers,
    required bool preferRelay,
    required bool createDataChannel,
  }) async {
    await close();

    final connection = await createPeerConnection({
      'iceServers': iceServers.map((server) => server.toJson()).toList(),
      'iceTransportPolicy': preferRelay ? 'relay' : 'all',
      'bundlePolicy': 'balanced',
      'rtcpMuxPolicy': 'require',
      'sdpSemantics': 'unified-plan',
    });

    connection.onIceCandidate = (candidate) {
      final rawCandidate = candidate.candidate;
      if (rawCandidate != null) {
        _registerCandidate(rawCandidate);
      }
      onLocalIceCandidate?.call({
        'candidate': rawCandidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    connection.onConnectionState = (state) {
      onConnectionStateChanged?.call(state.name);
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        onConnectionPathChanged?.call(_resolvePath());
      }
    };

    connection.onIceConnectionState = (state) {
      onIceConnectionStateChanged?.call(state.name);
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        onConnectionPathChanged?.call(_resolvePath());
      }
    };

    connection.onDataChannel = (channel) {
      _attachDataChannel(channel);
    };

    if (createDataChannel) {
      final channel = await connection.createDataChannel(
        'scn-data',
        RTCDataChannelInit()
          ..ordered = true
          ..maxRetransmits = 30,
      );
      _attachDataChannel(channel);
    }

    _peerConnection = connection;
  }

  void _attachDataChannel(RTCDataChannel channel) {
    _dataChannel = channel;
    channel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        onConnectionPathChanged?.call(_resolvePath());
      }
      onDataChannelStateChanged?.call(state.name);
    };
    channel.onMessage = (message) {
      if (message.isBinary) return;
      try {
        onDataMessage?.call(jsonDecode(message.text) as Map<String, dynamic>);
      } catch (e) {
        AppLogger.log('Invalid datachannel payload: $e');
      }
    };
  }

  void _registerCandidate(String candidate) {
    if (candidate.contains(' typ relay ')) {
      _candidateTypes.add('relay');
    } else if (candidate.contains(' typ srflx ')) {
      _candidateTypes.add('srflx');
    } else if (candidate.contains(' typ host ')) {
      _candidateTypes.add('host');
    }
  }

  PeerConnectionPath _resolvePath() {
    if (_candidateTypes.contains('relay')) {
      return PeerConnectionPath.relayed;
    }
    if (_candidateTypes.contains('srflx') || _candidateTypes.contains('host')) {
      return PeerConnectionPath.direct;
    }
    return PeerConnectionPath.unknown;
  }
}
