import 'package:scn/models/remote_peer.dart';

enum InternetFileTransportMode {
  legacyHttpDirect,
  webRtcDataChannelPlanned,
}

class InternetTransportPlan {
  final PeerTransport controlTransport;
  final InternetFileTransportMode fileTransportMode;
  final String summary;
  final String details;

  const InternetTransportPlan({
    required this.controlTransport,
    required this.fileTransportMode,
    required this.summary,
    required this.details,
  });
}

class InternetTransportPlanner {
  const InternetTransportPlanner();

  InternetTransportPlan planFor(PeerConnectionPath path) {
    switch (path) {
      case PeerConnectionPath.relayed:
        return const InternetTransportPlan(
          controlTransport: PeerTransport.webRtcDataChannel,
          fileTransportMode: InternetFileTransportMode.webRtcDataChannelPlanned,
          summary: 'TURN relay in use',
          details:
              'Control traffic already goes through WebRTC. File transfer should migrate to chunked DataChannel instead of assuming direct HTTP reachability.',
        );
      case PeerConnectionPath.direct:
        return const InternetTransportPlan(
          controlTransport: PeerTransport.webRtcDataChannel,
          fileTransportMode: InternetFileTransportMode.webRtcDataChannelPlanned,
          summary: 'Direct WebRTC path available',
          details:
              'Control traffic is ready on DataChannel. Files can still use legacy HTTP only for trusted LAN/direct reachability during migration.',
        );
      case PeerConnectionPath.legacyDirect:
        return const InternetTransportPlan(
          controlTransport: PeerTransport.legacySocket,
          fileTransportMode: InternetFileTransportMode.legacyHttpDirect,
          summary: 'Legacy direct path',
          details:
              'This path still relies on direct reachability and should be treated as compatibility mode only.',
        );
      case PeerConnectionPath.lan:
        return const InternetTransportPlan(
          controlTransport: PeerTransport.legacySocket,
          fileTransportMode: InternetFileTransportMode.legacyHttpDirect,
          summary: 'LAN path',
          details:
              'Local-network transport remains unchanged and can continue using direct HTTP.',
        );
      case PeerConnectionPath.unknown:
        return const InternetTransportPlan(
          controlTransport: PeerTransport.unknown,
          fileTransportMode: InternetFileTransportMode.webRtcDataChannelPlanned,
          summary: 'Transport path not resolved yet',
          details:
              'Show diagnostics and wait for ICE completion before promising direct reachability.',
        );
    }
  }
}
