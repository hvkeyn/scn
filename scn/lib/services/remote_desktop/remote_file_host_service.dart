import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;

import 'package:scn/models/remote_desktop_models.dart';
import 'package:scn/models/remote_file_models.dart';
import 'package:scn/utils/logger.dart';

class _FsSession {
  final String fsToken;
  final String sessionId;
  final String viewerDeviceId;
  final String viewerAlias;
  final String viewerAddress;
  DateTime lastActivity;
  bool readOnly;

  _FsSession({
    required this.fsToken,
    required this.sessionId,
    required this.viewerDeviceId,
    required this.viewerAlias,
    required this.viewerAddress,
    required this.readOnly,
  }) : lastActivity = DateTime.now();
}

/// Хост-сервис для удалённого файлового менеджера.
/// Отдельный fsToken-flow, чтобы не зависеть от RD-сессии видео/аудио.
class RemoteFileHostService extends ChangeNotifier {
  final Map<String, _FsSession> _sessions = {};
  final Random _random = Random.secure();
  final Duration _sessionIdleTimeout = const Duration(minutes: 15);

  RemoteDesktopSettings _settings = const RemoteDesktopSettings();
  Timer? _gcTimer;

  RemoteFileHostService() {
    _gcTimer = Timer.periodic(const Duration(minutes: 1), (_) => _gc());
  }

  void applySettings(RemoteDesktopSettings settings) {
    _settings = settings;
  }

  // ---------------- HTTP entrypoints ----------------

  /// POST /api/rd/fs/connect — авторизация (password / trusted) и выдача fsToken.
  Future<shelf.Response> handleConnect(shelf.Request request) async {
    if (!_settings.enabled || !_settings.fileManagerEnabled) {
      return _json(403, {'error': 'file manager disabled'});
    }
    Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return _json(400, {'error': 'bad body'});
    }
    final viewerDeviceId = body['viewerDeviceId'] as String? ?? '';
    final viewerAlias = body['viewerAlias'] as String? ?? 'Unknown';
    final password = body['password'] as String?;

    final isTrusted = _settings.trustedPeerIds.contains(viewerDeviceId);
    final passwordOk = password != null &&
        _settings.password != null &&
        password == _settings.password;

    if (!isTrusted && !passwordOk) {
      return _json(403, {'error': 'invalid credentials'});
    }

    final fsToken = _generateId();
    final sessionId = _generateId();
    final session = _FsSession(
      fsToken: fsToken,
      sessionId: sessionId,
      viewerDeviceId: viewerDeviceId,
      viewerAlias: viewerAlias,
      viewerAddress: _peerAddressFromRequest(request),
      readOnly: _settings.fileManagerReadOnly,
    );
    _sessions[fsToken] = session;
    notifyListeners();

    final roots = await _listRoots();
    return _json(200, RemoteFileSessionGrant(
      fsToken: fsToken,
      sessionId: sessionId,
      readOnly: session.readOnly,
      roots: roots,
    ).toJson());
  }

  /// GET /api/rd/fs/list?token=...&path=...
  Future<shelf.Response> handleList(shelf.Request request) async {
    final session = _authorize(request);
    if (session == null) return _json(401, {'error': 'unauthorized'});
    final path = request.url.queryParameters['path'] ?? '';
    try {
      if (path.isEmpty) {
        final roots = await _listRoots();
        return _json(200, RemoteFileListing(
          path: '',
          parentPath: null,
          entries: roots,
        ).toJson());
      }
      final dir = Directory(path);
      if (!await dir.exists()) {
        return _json(404, {'error': 'not found'});
      }
      if (!_isAllowed(path)) {
        return _json(403, {'error': 'path not allowed'});
      }
      final entries = <RemoteFileEntry>[];
      await for (final entity in dir.list(followLinks: false)) {
        try {
          final stat = await entity.stat();
          final name = p.basename(entity.path);
          RemoteFileEntryType type;
          if (entity is Directory) {
            type = RemoteFileEntryType.directory;
          } else if (entity is Link) {
            type = RemoteFileEntryType.symlink;
          } else {
            type = RemoteFileEntryType.file;
          }
          entries.add(RemoteFileEntry(
            name: name,
            path: entity.path,
            type: type,
            size: stat.size,
            modified: stat.modified,
            isHidden: name.startsWith('.'),
          ));
        } catch (_) {
          // пропускаем файлы без доступа
        }
      }
      entries.sort((a, b) {
        if (a.isDirectory != b.isDirectory) {
          return a.isDirectory ? -1 : 1;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      final parent = p.dirname(path);
      return _json(200, RemoteFileListing(
        path: path,
        parentPath: (parent == path || parent.isEmpty) ? null : parent,
        entries: entries,
      ).toJson());
    } catch (e) {
      return _json(500, {'error': e.toString()});
    }
  }

  /// GET /api/rd/fs/download?token=...&path=... (поддержка Range).
  Future<shelf.Response> handleDownload(shelf.Request request) async {
    final session = _authorize(request);
    if (session == null) return _json(401, {'error': 'unauthorized'});
    final path = request.url.queryParameters['path'];
    if (path == null) return _json(400, {'error': 'missing path'});
    if (!_isAllowed(path)) return _json(403, {'error': 'forbidden'});
    final file = File(path);
    if (!await file.exists()) return _json(404, {'error': 'not found'});

    final length = await file.length();
    int start = 0;
    int end = length - 1;

    final rangeHeader = request.headers['range'];
    bool partial = false;
    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final spec = rangeHeader.substring(6).split('-');
      if (spec.length == 2) {
        if (spec[0].isNotEmpty) start = int.tryParse(spec[0]) ?? 0;
        if (spec[1].isNotEmpty) end = int.tryParse(spec[1]) ?? end;
        if (start < 0) start = 0;
        if (end >= length) end = length - 1;
        partial = true;
      }
    }
    final contentLength = end - start + 1;
    final stream = file.openRead(start, end + 1);
    final headers = <String, String>{
      'content-length': '$contentLength',
      'content-type': 'application/octet-stream',
      'accept-ranges': 'bytes',
      if (partial) 'content-range': 'bytes $start-$end/$length',
      'x-file-name': Uri.encodeComponent(p.basename(path)),
      'x-file-size': '$length',
    };
    return shelf.Response(partial ? 206 : 200, body: stream, headers: headers);
  }

  /// POST /api/rd/fs/upload?token=...&path=... (тело — байты, поддержка Content-Range).
  Future<shelf.Response> handleUpload(shelf.Request request) async {
    final session = _authorize(request);
    if (session == null) return _json(401, {'error': 'unauthorized'});
    if (session.readOnly) return _json(403, {'error': 'read only'});
    final path = request.url.queryParameters['path'];
    if (path == null) return _json(400, {'error': 'missing path'});
    if (!_isAllowed(path)) return _json(403, {'error': 'forbidden'});

    final file = File(path);
    final crange = request.headers['content-range'];

    int start = 0;
    bool append = false;
    if (crange != null && crange.startsWith('bytes ')) {
      final spec = crange.substring(6).split('/');
      final part = spec.first.split('-');
      if (part.length == 2) {
        start = int.tryParse(part[0]) ?? 0;
        append = start > 0;
      }
    }

    try {
      final mode = append ? FileMode.append : FileMode.write;
      final raf = await file.open(mode: mode);
      try {
        if (!append && start == 0) {
          await raf.truncate(0);
        }
        if (start > 0) {
          await raf.setPosition(start);
        }
        await for (final chunk in request.read()) {
          await raf.writeFrom(chunk);
        }
      } finally {
        await raf.close();
      }
      return _json(200, {'status': 'ok'});
    } catch (e) {
      return _json(500, {'error': e.toString()});
    }
  }

  /// POST /api/rd/fs/mkdir?token=...&path=...
  Future<shelf.Response> handleMkdir(shelf.Request request) async {
    final session = _authorize(request);
    if (session == null) return _json(401, {'error': 'unauthorized'});
    if (session.readOnly) return _json(403, {'error': 'read only'});
    final path = request.url.queryParameters['path'];
    if (path == null) return _json(400, {'error': 'missing path'});
    if (!_isAllowed(path)) return _json(403, {'error': 'forbidden'});
    try {
      await Directory(path).create(recursive: true);
      return _json(200, {'status': 'ok'});
    } catch (e) {
      return _json(500, {'error': e.toString()});
    }
  }

  /// POST /api/rd/fs/delete?token=...&path=...&recursive=true
  Future<shelf.Response> handleDelete(shelf.Request request) async {
    final session = _authorize(request);
    if (session == null) return _json(401, {'error': 'unauthorized'});
    if (session.readOnly) return _json(403, {'error': 'read only'});
    final path = request.url.queryParameters['path'];
    final recursive = request.url.queryParameters['recursive'] == 'true';
    if (path == null) return _json(400, {'error': 'missing path'});
    if (!_isAllowed(path)) return _json(403, {'error': 'forbidden'});
    try {
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        await Directory(path).delete(recursive: recursive);
      } else if (type == FileSystemEntityType.notFound) {
        return _json(404, {'error': 'not found'});
      } else {
        await File(path).delete();
      }
      return _json(200, {'status': 'ok'});
    } catch (e) {
      return _json(500, {'error': e.toString()});
    }
  }

  /// POST /api/rd/fs/rename?token=...&from=...&to=...
  Future<shelf.Response> handleRename(shelf.Request request) async {
    final session = _authorize(request);
    if (session == null) return _json(401, {'error': 'unauthorized'});
    if (session.readOnly) return _json(403, {'error': 'read only'});
    final from = request.url.queryParameters['from'];
    final to = request.url.queryParameters['to'];
    if (from == null || to == null) return _json(400, {'error': 'missing'});
    if (!_isAllowed(from) || !_isAllowed(to)) {
      return _json(403, {'error': 'forbidden'});
    }
    try {
      final type = await FileSystemEntity.type(from, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        await Directory(from).rename(to);
      } else if (type == FileSystemEntityType.notFound) {
        return _json(404, {'error': 'not found'});
      } else {
        await File(from).rename(to);
      }
      return _json(200, {'status': 'ok'});
    } catch (e) {
      return _json(500, {'error': e.toString()});
    }
  }

  /// POST /api/rd/fs/disconnect?token=...
  Future<shelf.Response> handleDisconnect(shelf.Request request) async {
    final session = _authorize(request);
    if (session == null) return _json(401, {'error': 'unauthorized'});
    _sessions.remove(session.fsToken);
    notifyListeners();
    return _json(200, {'status': 'ok'});
  }

  // ---------------- helpers ----------------

  _FsSession? _authorize(shelf.Request request) {
    final token = request.url.queryParameters['token'] ??
        request.headers['x-fs-token'];
    if (token == null) return null;
    final s = _sessions[token];
    if (s != null) {
      s.lastActivity = DateTime.now();
    }
    return s;
  }

  bool _isAllowed(String path) {
    if (_settings.fileManagerAllowedRoots.isEmpty) return true;
    final norm = p.normalize(path).toLowerCase();
    for (final root in _settings.fileManagerAllowedRoots) {
      final r = p.normalize(root).toLowerCase();
      if (norm == r || norm.startsWith(r + p.separator.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  Future<List<RemoteFileEntry>> _listRoots() async {
    final allowed = _settings.fileManagerAllowedRoots;
    if (allowed.isNotEmpty) {
      final result = <RemoteFileEntry>[];
      for (final root in allowed) {
        try {
          final stat = await FileStat.stat(root);
          result.add(RemoteFileEntry(
            name: root,
            path: root,
            type: RemoteFileEntryType.directory,
            modified: stat.modified,
          ));
        } catch (_) {}
      }
      return result;
    }
    if (Platform.isWindows) {
      final drives = <RemoteFileEntry>[];
      for (final letter in 'CDEFGHIJKLMNOPQRSTUVWXYZAB'.split('')) {
        final root = '$letter:\\';
        if (await Directory(root).exists()) {
          drives.add(RemoteFileEntry(
            name: '$letter:',
            path: root,
            type: RemoteFileEntryType.drive,
          ));
        }
      }
      return drives;
    }
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '/';
    return [
      RemoteFileEntry(
        name: 'Home',
        path: home,
        type: RemoteFileEntryType.directory,
      ),
      const RemoteFileEntry(
        name: '/',
        path: '/',
        type: RemoteFileEntryType.directory,
      ),
    ];
  }

  shelf.Response _json(int status, Map<String, dynamic> body) =>
      shelf.Response(
        status,
        body: jsonEncode(body),
        headers: {'Content-Type': 'application/json'},
      );

  String _peerAddressFromRequest(shelf.Request request) {
    final connInfo = request.context['shelf.io.connection_info'];
    if (connInfo is HttpConnectionInfo) {
      return connInfo.remoteAddress.address;
    }
    return request.headers['x-forwarded-for'] ??
        request.headers['remote-addr'] ??
        'unknown';
  }

  void _gc() {
    final now = DateTime.now();
    _sessions.removeWhere(
        (_, s) => now.difference(s.lastActivity) > _sessionIdleTimeout);
  }

  String _generateId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> shutdown() async {
    _gcTimer?.cancel();
    _gcTimer = null;
    _sessions.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _gcTimer?.cancel();
    _gcTimer = null;
    _sessions.clear();
    super.dispose();
    AppLogger.log('RemoteFileHostService disposed');
  }
}
