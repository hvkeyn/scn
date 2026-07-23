import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:scn/services/remote_desktop/remote_desktop_relay_service.dart';
import 'package:scn/utils/logger.dart';

class UpdateInfo {
  final String version;
  final int build;
  final String? versionString;
  final String url;
  final String? sha256;
  final int? size;
  final List<String>? changes;
  final String? changesUrl;
  final bool mandatory;
  final DateTime? releasedAt;

  UpdateInfo({
    required this.version,
    required this.build,
    required this.url,
    this.versionString,
    this.sha256,
    this.size,
    this.changes,
    this.changesUrl,
    this.mandatory = false,
    this.releasedAt,
  });

  String get displayVersion => versionString?.isNotEmpty == true
      ? versionString!
      : '$version+$build';

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final versionString = json['versionString'] as String?;
    final build = json['build'] is int
        ? json['build'] as int
        : int.tryParse('${json['build'] ?? ''}') ?? _parseBuild(versionString);
    return UpdateInfo(
      version: json['version'] as String? ?? _parseVersion(versionString),
      build: build,
      versionString: versionString,
      url: json['url'] as String,
      sha256: json['sha256'] as String?,
      size: json['size'] is int ? json['size'] as int : null,
      changes: (json['changes'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList(),
      changesUrl: json['changesUrl'] as String?,
      mandatory: json['mandatory'] as bool? ?? false,
      releasedAt: json['releasedAt'] != null
          ? DateTime.tryParse(json['releasedAt'].toString())
          : null,
    );
  }

  static int _parseBuild(String? versionString) {
    if (versionString == null || !versionString.contains('+')) return 0;
    final parts = versionString.split('+');
    return int.tryParse(parts.last) ?? 0;
  }

  static String _parseVersion(String? versionString) {
    if (versionString == null || versionString.isEmpty) return '0.0.0';
    return versionString.split('+').first;
  }
}

class UpdateService {
  /// Same host as WAN RD relay (`ws://…/ws` → `http://…/scn/update.json`).
  /// HTTP works on Win7 (no Dart TLS abort).
  static String get updateManifestUrl =>
      manifestUrlFromRelayWs(defaultRemoteDesktopRelayUrl);

  static const String legacyHttpsManifestUrl =
      'https://drawrandom.telsys.online/scn/update.json';

  static const Duration _timeout = Duration(seconds: 15);
  static const Duration _downloadTimeout = Duration(minutes: 15);

  static String manifestUrlFromRelayWs(String relayWsUrl) {
    var base = relayWsUrl.trim();
    if (base.startsWith('ws://')) {
      base = 'http://${base.substring(5)}';
    } else if (base.startsWith('wss://')) {
      // Win7 cannot use TLS; fall back to cleartext host if possible.
      base = 'http://${base.substring(6)}';
    }
    base = base.replaceFirst(RegExp(r'/ws/?$'), '');
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    return '$base/scn/update.json';
  }

  Future<UpdateInfo?> checkForUpdate() async {
    if (!Platform.isWindows) return null;
    try {
      final latest = await fetchLatest();
      if (latest == null) return null;

      final current = await _getCurrentVersion();
      final isNewer = _isNewer(latest, current);
      if (!isNewer) return null;

      AppLogger.log(
        'Update available: ${latest.displayVersion} (current ${current.version}+${current.build})',
      );
      return latest;
    } catch (e) {
      AppLogger.log('Update check failed: $e');
      return null;
    }
  }

  Future<UpdateInfo?> fetchLatest() async {
    final urls = <String>[
      updateManifestUrl,
      if (!identical(updateManifestUrl, legacyHttpsManifestUrl))
        legacyHttpsManifestUrl,
    ];
    // Prefer relay HTTP; skip legacy HTTPS on Win7 (TLS abort).
    final win7 = Platform.environment['SCN_WIN7'] == '1';
    for (final url in urls) {
      if (win7 && url.startsWith('https://')) {
        AppLogger.log('UpdateService: skip HTTPS on Win7: $url');
        continue;
      }
      try {
        AppLogger.log('UpdateService: fetch $url');
        final response = await http.get(Uri.parse(url)).timeout(_timeout);
        if (response.statusCode != 200) {
          AppLogger.log('Update manifest HTTP ${response.statusCode} for $url');
          continue;
        }
        final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
        return UpdateInfo.fromJson(jsonData);
      } catch (e) {
        AppLogger.log('Failed to fetch update manifest ($url): $e');
      }
    }
    return null;
  }

  Future<List<String>> loadChanges(UpdateInfo info) async {
    if (info.changes != null && info.changes!.isNotEmpty) {
      return info.changes!;
    }
    if (info.changesUrl == null || info.changesUrl!.isEmpty) {
      return const [];
    }
    if (Platform.environment['SCN_WIN7'] == '1' &&
        info.changesUrl!.startsWith('https://')) {
      return const [];
    }
    try {
      final response =
          await http.get(Uri.parse(info.changesUrl!)).timeout(_timeout);
      if (response.statusCode != 200) return const [];
      final lines = const LineSplitter()
          .convert(response.body)
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      return lines;
    } catch (_) {
      return const [];
    }
  }

  Future<void> downloadAndInstall(UpdateInfo info) async {
    if (!Platform.isWindows) return;
    if (Platform.environment['SCN_WIN7'] == '1' &&
        info.url.startsWith('https://')) {
      throw Exception(
          'HTTPS updates are not supported on Windows 7. Use HTTP relay URL.');
    }
    final tempDir = await getTemporaryDirectory();
    final updateDir = Directory(p.join(
      tempDir.path,
      'scn_update_${DateTime.now().millisecondsSinceEpoch}',
    ));
    await updateDir.create(recursive: true);

    final zipPath = p.join(updateDir.path, 'update.zip');
    AppLogger.log('Downloading update: ${info.url}');
    await _downloadFile(info.url, zipPath);

    if (info.sha256 != null && info.sha256!.isNotEmpty) {
      final actual = await _sha256OfFile(zipPath);
      if (actual.toLowerCase() != info.sha256!.toLowerCase()) {
        throw Exception('SHA256 mismatch for update package');
      }
    }

    final exePath = Platform.resolvedExecutable;
    final appDir = File(exePath).parent.path;
    final scriptPath = p.join(updateDir.path, 'apply_update.ps1');
    final pid = pidForUpdate();

    final script = _buildUpdateScript(
      pid: pid,
      zipPath: zipPath,
      targetDir: appDir,
      exePath: exePath,
      workDir: updateDir.path,
    );

    await File(scriptPath).writeAsString(script);

    await Process.start(
      'powershell.exe',
      ['-ExecutionPolicy', 'Bypass', '-File', scriptPath],
      runInShell: true,
      mode: ProcessStartMode.detached,
    );

    exit(0);
  }

  int pidForUpdate() => pid;

  Future<void> _downloadFile(String url, String targetPath) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('Failed to download update: ${response.statusCode}');
      }
      final file = File(targetPath);
      final sink = file.openWrite();
      // Large portable zips — no short timeout on body stream.
      await response.pipe(sink).timeout(_downloadTimeout);
      await sink.flush();
      await sink.close();
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _sha256OfFile(String path) async {
    final file = File(path);
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  Future<_CurrentVersion> _getCurrentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return _CurrentVersion(
      version: info.version,
      build: int.tryParse(info.buildNumber) ?? 0,
    );
  }

  bool _isNewer(UpdateInfo latest, _CurrentVersion current) {
    if (latest.build != 0 && current.build != 0) {
      if (latest.build > current.build) return true;
      if (latest.build < current.build) return false;
    }
    return _compareSemver(latest.version, current.version) > 0;
  }

  int _compareSemver(String a, String b) {
    final pa = a.split('.');
    final pb = b.split('.');
    for (var i = 0; i < 3; i++) {
      final ai = i < pa.length ? int.tryParse(pa[i]) ?? 0 : 0;
      final bi = i < pb.length ? int.tryParse(pb[i]) ?? 0 : 0;
      if (ai != bi) return ai.compareTo(bi);
    }
    return 0;
  }

  String _buildUpdateScript({
    required int pid,
    required String zipPath,
    required String targetDir,
    required String exePath,
    required String workDir,
  }) {
    // PowerShell's $PID is a built-in read-only automatic variable — never assign to it.
    return '''
\$ErrorActionPreference = "Continue"
\$appPid = $pid
\$zipPath = "$zipPath"
\$targetDir = "$targetDir"
\$exePath = "$exePath"
\$workDir = "$workDir\\extracted"

while (Get-Process -Id \$appPid -ErrorAction SilentlyContinue) {
  Start-Sleep -Milliseconds 300
}

Start-Sleep -Milliseconds 500

if (Test-Path \$workDir) { Remove-Item \$workDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path \$workDir -Force | Out-Null

Expand-Archive -Path \$zipPath -DestinationPath \$workDir -Force

Copy-Item -Path (Join-Path \$workDir '*') -Destination \$targetDir -Recurse -Force

Start-Process -FilePath \$exePath

Remove-Item \$zipPath -Force -ErrorAction SilentlyContinue
Remove-Item \$workDir -Recurse -Force -ErrorAction SilentlyContinue
''';
  }
}

class _CurrentVersion {
  final String version;
  final int build;

  _CurrentVersion({required this.version, required this.build});
}
