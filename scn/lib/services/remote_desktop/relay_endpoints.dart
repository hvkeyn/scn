/// Built-in WAN relay candidates. Host registers on all healthy ones;
/// viewer picks the nearest where the target host is online.
class RdRelayEndpoint {
  const RdRelayEndpoint({
    required this.id,
    required this.label,
    required this.wsUrl,
    required this.httpBase,
    required this.region,
  });

  final String id;
  final String label;
  final String wsUrl;
  final String httpBase;
  final String region; // 'ru' | 'eu' | ...

  Uri get healthUri => Uri.parse('$httpBase/api/v1/health');
  Uri get hostsUri => Uri.parse('$httpBase/api/v1/rd/hosts');
  Uri lookupUri(String code) =>
      Uri.parse('$httpBase/api/v1/rd/lookup').replace(queryParameters: {
        'code': code,
      });
}

/// Prefer RU (Yandex) for RF clients; DE kept as fallback.
const List<RdRelayEndpoint> kRdRelayEndpoints = [
  RdRelayEndpoint(
    id: 'ru',
    label: 'Yandex RU',
    wsUrl: 'ws://158.160.104.107:53319/ws',
    httpBase: 'http://158.160.104.107:53319',
    region: 'ru',
  ),
  RdRelayEndpoint(
    id: 'de',
    label: 'DE',
    wsUrl: 'ws://5.187.4.132:53319/ws',
    httpBase: 'http://5.187.4.132:53319',
    region: 'eu',
  ),
];

/// Legacy single default (DE) — used only as last-resort fallback.
const String defaultRemoteDesktopRelayUrl = 'ws://5.187.4.132:53319/ws';
