import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
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
  static const String updateManifestUrl =
      'https://drawrandom.telsys.online/scn/update.json';
  static const Duration _timeout = Duration(seconds: 10);

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
    try {
      final response = await http
          .get(Uri.parse(updateManifestUrl))
          .timeout(_timeout);
      if (response.statusCode != 200) {
        AppLogger.log('Update manifest HTTP ${response.statusCode}');
        return null;
      }
      final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
      final info = UpdateInfo.fromJson(jsonData);
      return info;
    } catch (e) {
      AppLogger.log('Failed to fetch update manifest: $e');
      return null;
    }
  }

  Future<List<String>> loadChanges(UpdateInfo info) async {
    if (info.changes != null && info.changes!.isNotEmpty) {
      return info.changes!;
    }
    if (info.changesUrl == null || info.changesUrl!.isEmpty) {
      return const [];
    }
    try {
      final response = await http
          .get(Uri.parse(info.changesUrl!))
          .timeout(_timeout);
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
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close().timeout(_timeout);
    if (response.statusCode != 200) {
      throw Exception('Failed to download update: ${response.statusCode}');
    }
    final file = File(targetPath);
    final sink = file.openWrite();
    await response.pipe(sink);
    await sink.flush();
    await sink.close();
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
    return '''
\$ErrorActionPreference = "Continue"
\$pid = $pid
\$zipPath = "$zipPath"
\$targetDir = "$targetDir"
\$exePath = "$exePath"
\$workDir = "$workDir\\extracted"

while (Get-Process -Id \$pid -ErrorAction SilentlyContinue) {
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
