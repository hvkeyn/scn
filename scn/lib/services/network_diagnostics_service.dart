import 'package:scn/services/stun_service.dart';

enum NetworkReachability {
  unknown,
  directPossible,
  relayRecommended,
  relayRequired,
  unreachable,
}

class NetworkDiagnosticsResult {
  final NatInfo? natInfo;
  final NetworkReachability reachability;
  final bool canAttemptDirect;
  final bool relayRecommended;
  final bool relayRequired;
  final String summary;
  final String recommendation;

  const NetworkDiagnosticsResult({
    required this.natInfo,
    required this.reachability,
    required this.canAttemptDirect,
    required this.relayRecommended,
    required this.relayRequired,
    required this.summary,
    required this.recommendation,
  });
}

class NetworkDiagnosticsService {
  final StunService _stunService;

  NetworkDiagnosticsService({StunService? stunService})
      : _stunService = stunService ?? StunService();

  Future<NetworkDiagnosticsResult> analyze({int localPort = 0}) async {
    final natInfo = await _stunService.discoverNat(localPort: localPort);
    if (natInfo == null) {
      return const NetworkDiagnosticsResult(
        natInfo: null,
        reachability: NetworkReachability.unreachable,
        canAttemptDirect: false,
        relayRecommended: true,
        relayRequired: true,
        summary: 'Public network mapping was not detected',
        recommendation:
            'Use signaling plus TURN relay. Check outbound UDP/firewall rules only if TURN also fails.',
      );
    }

    switch (natInfo.natType) {
      case NatType.openInternet:
      case NatType.fullCone:
        return NetworkDiagnosticsResult(
          natInfo: natInfo,
          reachability: NetworkReachability.directPossible,
          canAttemptDirect: true,
          relayRecommended: false,
          relayRequired: false,
          summary: 'Direct WebRTC should work in most networks',
          recommendation:
              'STUN should be enough in many cases, but keep TURN available as backup.',
        );
      case NatType.restrictedCone:
        return NetworkDiagnosticsResult(
          natInfo: natInfo,
          reachability: NetworkReachability.directPossible,
          canAttemptDirect: true,
          relayRecommended: true,
          relayRequired: false,
          summary:
              'Direct WebRTC may work, but some peers will still need TURN',
          recommendation:
              'Attempt direct ICE first and keep TURN enabled as normal fallback.',
        );
      case NatType.portRestricted:
        return NetworkDiagnosticsResult(
          natInfo: natInfo,
          reachability: NetworkReachability.relayRecommended,
          canAttemptDirect: true,
          relayRecommended: true,
          relayRequired: false,
          summary: 'Port-restricted NAT detected',
          recommendation:
              'Direct WebRTC can fail often. TURN relay should be available by default.',
        );
      case NatType.symmetric:
        return NetworkDiagnosticsResult(
          natInfo: natInfo,
          reachability: NetworkReachability.relayRequired,
          canAttemptDirect: false,
          relayRecommended: true,
          relayRequired: true,
          summary: 'Symmetric NAT or CGNAT-like behavior detected',
          recommendation:
              'Expect TURN relay. Manual port forwarding is optional and only helps some routers.',
        );
      case NatType.unknown:
        return NetworkDiagnosticsResult(
          natInfo: natInfo,
          reachability: NetworkReachability.relayRecommended,
          canAttemptDirect: true,
          relayRecommended: true,
          relayRequired: false,
          summary: 'NAT behavior is unknown',
          recommendation:
              'Attempt direct ICE, but show relay as the normal fallback path.',
        );
    }
  }
}
