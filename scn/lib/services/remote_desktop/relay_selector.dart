import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:scn/services/remote_desktop/relay_endpoints.dart';
import 'package:scn/utils/logger.dart';

class RdRelayProbe {
  const RdRelayProbe({
    required this.endpoint,
    required this.ok,
    required this.rttMs,
    this.hosts = 0,
    this.error,
  });

  final RdRelayEndpoint endpoint;
  final bool ok;
  final int rttMs;
  final int hosts;
  final String? error;
}

/// Probes relays by HTTP health RTT and (optionally) host presence.
class RdRelaySelector {
  RdRelaySelector._();

  static Future<List<RdRelayProbe>> probeAll({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final results = await Future.wait(
      kRdRelayEndpoints.map((e) => _probeOne(e, timeout)),
    );
    final sorted = [...results]..sort((a, b) {
        if (a.ok != b.ok) return a.ok ? -1 : 1;
        // Prefer RU when RTT is close (within 40ms).
        if (a.ok && b.ok && (a.rttMs - b.rttMs).abs() <= 40) {
          if (a.endpoint.region == 'ru' && b.endpoint.region != 'ru') {
            return -1;
          }
          if (b.endpoint.region == 'ru' && a.endpoint.region != 'ru') {
            return 1;
          }
        }
        return a.rttMs.compareTo(b.rttMs);
      });
    for (final p in sorted) {
      AppLogger.log(
          'RD relay probe ${p.endpoint.id}: ok=${p.ok} rtt=${p.rttMs}ms '
          'hosts=${p.hosts} err=${p.error ?? '-'}');
    }
    return sorted;
  }

  /// Best healthy endpoint by RTT (RU bias). Null if all down.
  static Future<RdRelayEndpoint?> pickFastest() async {
    final probes = await probeAll();
    for (final p in probes) {
      if (p.ok) return p.endpoint;
    }
    return null;
  }

  /// Pick nearest relay where [code] host is currently registered.
  static Future<RdRelayEndpoint?> pickForHostCode(String code) async {
    final digits = code.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return pickFastest();

    final probes = await probeAll();
    for (final p in probes) {
      if (!p.ok) continue;
      final found = await _hostPresent(p.endpoint, digits);
      AppLogger.log(
          'RD relay lookup ${p.endpoint.id}: code=$digits found=$found');
      if (found) return p.endpoint;
    }
    // Host not listed yet (race) — fall back to fastest healthy.
    return pickFastest();
  }

  static Future<RdRelayProbe> _probeOne(
      RdRelayEndpoint endpoint, Duration timeout) async {
    final sw = Stopwatch()..start();
    try {
      final client = HttpClient()..connectionTimeout = timeout;
      try {
        final req = await client.getUrl(endpoint.healthUri);
        final resp = await req.close().timeout(timeout);
        final body = await resp.transform(utf8.decoder).join();
        sw.stop();
        if (resp.statusCode != 200) {
          return RdRelayProbe(
            endpoint: endpoint,
            ok: false,
            rttMs: sw.elapsedMilliseconds,
            error: 'http ${resp.statusCode}',
          );
        }
        var hosts = 0;
        try {
          final json = jsonDecode(body) as Map<String, dynamic>;
          hosts = (json['hosts'] as num?)?.toInt() ?? 0;
          final okFlag = json['ok'] == true;
          if (!okFlag) {
            return RdRelayProbe(
              endpoint: endpoint,
              ok: false,
              rttMs: sw.elapsedMilliseconds,
              hosts: hosts,
              error: 'ok=false',
            );
          }
        } catch (_) {}
        return RdRelayProbe(
          endpoint: endpoint,
          ok: true,
          rttMs: sw.elapsedMilliseconds,
          hosts: hosts,
        );
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      sw.stop();
      return RdRelayProbe(
        endpoint: endpoint,
        ok: false,
        rttMs: sw.elapsedMilliseconds,
        error: e.toString(),
      );
    }
  }

  static Future<bool> _hostPresent(
      RdRelayEndpoint endpoint, String codeDigits) async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 3);
      try {
        // Prefer dedicated lookup; fall back to hosts list.
        final lookupReq = await client.getUrl(endpoint.lookupUri(codeDigits));
        final lookupResp =
            await lookupReq.close().timeout(const Duration(seconds: 3));
        if (lookupResp.statusCode == 200) {
          final body = await lookupResp.transform(utf8.decoder).join();
          final json = jsonDecode(body) as Map<String, dynamic>;
          if (json['found'] == true) return true;
          if (json.containsKey('found')) return false;
        }

        final req = await client.getUrl(endpoint.hostsUri);
        final resp = await req.close().timeout(const Duration(seconds: 3));
        if (resp.statusCode != 200) return false;
        final body = await resp.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final hosts = (json['hosts'] as List?) ?? const [];
        for (final raw in hosts) {
          if (raw is! Map) continue;
          final c = raw['code']?.toString().replaceAll(RegExp(r'\D'), '') ?? '';
          if (c == codeDigits || c == codeDigits.padLeft(9, '0')) {
            return true;
          }
        }
        return false;
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      AppLogger.log('RD relay hostPresent ${endpoint.id} failed: $e');
      return false;
    }
  }
}
