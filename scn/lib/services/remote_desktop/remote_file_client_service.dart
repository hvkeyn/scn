import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:scn/models/remote_file_models.dart';
import 'package:scn/utils/logger.dart';

/// Клиент удалённой ФС: общается с RemoteFileHostService по HTTP.
class RemoteFileClientService extends ChangeNotifier {
  static const int _chunkSize = 1 << 20; // 1 MiB

  final http.Client _http = http.Client();
  final Uuid _uuid = const Uuid();

  String? _baseUrl;
  String? _fsToken;
  bool _readOnly = false;
  bool _connected = false;

  final List<FileTransferTask> _transfers = [];

  bool get isConnected => _connected;
  bool get isReadOnly => _readOnly;
  String? get baseUrl => _baseUrl;
  List<FileTransferTask> get transfers => List.unmodifiable(_transfers);

  /// Подключение / получение fsToken.
  Future<RemoteFileSessionGrant> connect(RemoteFileSessionParams p) async {
    final url = Uri.parse('http://${p.host}:${p.port}/api/rd/fs/connect');
    final resp = await _http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'viewerDeviceId': p.viewerDeviceId,
        'viewerAlias': p.viewerAlias,
        if (p.password != null) 'password': p.password,
      }),
    );
    if (resp.statusCode != 200) {
      throw HttpException('connect failed: ${resp.statusCode} ${resp.body}');
    }
    final grant = RemoteFileSessionGrant.fromJson(
        jsonDecode(resp.body) as Map<String, dynamic>);
    _baseUrl = 'http://${p.host}:${p.port}';
    _fsToken = grant.fsToken;
    _readOnly = grant.readOnly;
    _connected = true;
    notifyListeners();
    return grant;
  }

  Future<void> disconnect() async {
    final base = _baseUrl;
    final token = _fsToken;
    if (base != null && token != null) {
      try {
        await _http.post(Uri.parse('$base/api/rd/fs/disconnect?token=$token'));
      } catch (_) {}
    }
    _baseUrl = null;
    _fsToken = null;
    _connected = false;
    notifyListeners();
  }

  // ---- listing / mutations ----

  Future<RemoteFileListing> list(String path) async {
    _ensure();
    final url = Uri.parse(
        '$_baseUrl/api/rd/fs/list?token=$_fsToken&path=${Uri.encodeComponent(path)}');
    final resp = await _http.get(url);
    if (resp.statusCode != 200) {
      throw HttpException('list failed: ${resp.statusCode} ${resp.body}');
    }
    return RemoteFileListing.fromJson(
        jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<void> mkdir(String path) async {
    _ensure();
    final url = Uri.parse(
        '$_baseUrl/api/rd/fs/mkdir?token=$_fsToken&path=${Uri.encodeComponent(path)}');
    final resp = await _http.post(url);
    if (resp.statusCode != 200) {
      throw HttpException('mkdir failed: ${resp.body}');
    }
  }

  Future<void> delete(String path, {bool recursive = true}) async {
    _ensure();
    final url = Uri.parse(
        '$_baseUrl/api/rd/fs/delete?token=$_fsToken&path=${Uri.encodeComponent(path)}&recursive=$recursive');
    final resp = await _http.post(url);
    if (resp.statusCode != 200) {
      throw HttpException('delete failed: ${resp.body}');
    }
  }

  Future<void> rename(String from, String to) async {
    _ensure();
    final url = Uri.parse(
        '$_baseUrl/api/rd/fs/rename?token=$_fsToken&from=${Uri.encodeComponent(from)}&to=${Uri.encodeComponent(to)}');
    final resp = await _http.post(url);
    if (resp.statusCode != 200) {
      throw HttpException('rename failed: ${resp.body}');
    }
  }

  // ---- transfers ----

  /// Скачать удалённый файл -> на локальный путь.
  Future<FileTransferTask> downloadFile({
    required String remotePath,
    required String localPath,
    int? remoteSize,
  }) async {
    _ensure();
    final task = FileTransferTask(
      id: _uuid.v4(),
      sourcePath: remotePath,
      destPath: localPath,
      direction: FileTransferDirection.download,
      totalBytes: remoteSize ?? 0,
    );
    _transfers.add(task);
    notifyListeners();
    unawaited(_runDownload(task));
    return task;
  }

  Future<void> _runDownload(FileTransferTask task) async {
    try {
      task.state = FileTransferState.preparing;
      _bumpSpeed(task, 0);

      final outFile = File(task.destPath);
      await outFile.parent.create(recursive: true);
      final raf = await outFile.open(mode: FileMode.write);

      task.state = FileTransferState.inProgress;
      notifyListeners();

      final url = Uri.parse(
          '$_baseUrl/api/rd/fs/download?token=$_fsToken&path=${Uri.encodeComponent(task.sourcePath)}');
      final req = http.Request('GET', url);
      final streamed = await _http.send(req);
      if (streamed.statusCode != 200 && streamed.statusCode != 206) {
        throw HttpException('download status ${streamed.statusCode}');
      }
      final total = streamed.contentLength ?? task.totalBytes;
      if (total > 0) {
        // обновим totalBytes если был неизвестен
        if (task.totalBytes <= 0) {
          // ignore: invalid_use_of_protected_member
          task.transferredBytes = 0;
        }
      }

      final lastTick = _SpeedTicker();
      try {
        await for (final chunk in streamed.stream) {
          await raf.writeFrom(chunk);
          task.transferredBytes += chunk.length;
          _bumpSpeed(task, lastTick.tick(chunk.length));
        }
      } finally {
        await raf.close();
      }

      task.state = FileTransferState.completed;
      task.updatedAt = DateTime.now();
      notifyListeners();
    } catch (e) {
      task.state = FileTransferState.failed;
      task.errorMessage = e.toString();
      AppLogger.log('RD download failed: $e');
      notifyListeners();
    }
  }

  /// Загрузить локальный файл -> в удалённый путь (chunked Content-Range).
  Future<FileTransferTask> uploadFile({
    required String localPath,
    required String remotePath,
  }) async {
    _ensure();
    if (_readOnly) {
      throw const FileSystemException('remote fs is read only');
    }
    final localFile = File(localPath);
    final length = await localFile.length();
    final task = FileTransferTask(
      id: _uuid.v4(),
      sourcePath: localPath,
      destPath: remotePath,
      direction: FileTransferDirection.upload,
      totalBytes: length,
    );
    _transfers.add(task);
    notifyListeners();
    unawaited(_runUpload(task, localFile));
    return task;
  }

  Future<void> _runUpload(FileTransferTask task, File localFile) async {
    try {
      task.state = FileTransferState.inProgress;
      notifyListeners();
      final raf = await localFile.open();
      final lastTick = _SpeedTicker();
      try {
        int sent = 0;
        while (sent < task.totalBytes) {
          final remaining = task.totalBytes - sent;
          final size = remaining > _chunkSize ? _chunkSize : remaining;
          final chunk = await raf.read(size);
          await _putChunk(task.destPath, sent, task.totalBytes, chunk);
          sent += chunk.length;
          task.transferredBytes = sent;
          _bumpSpeed(task, lastTick.tick(chunk.length));
        }
      } finally {
        await raf.close();
      }
      task.state = FileTransferState.completed;
      task.updatedAt = DateTime.now();
      notifyListeners();
    } catch (e) {
      task.state = FileTransferState.failed;
      task.errorMessage = e.toString();
      AppLogger.log('RD upload failed: $e');
      notifyListeners();
    }
  }

  Future<void> _putChunk(
      String remotePath, int offset, int total, Uint8List chunk) async {
    final url = Uri.parse(
        '$_baseUrl/api/rd/fs/upload?token=$_fsToken&path=${Uri.encodeComponent(remotePath)}');
    final last = offset + chunk.length - 1;
    final resp = await _http.post(
      url,
      headers: {
        'Content-Type': 'application/octet-stream',
        'Content-Range': 'bytes $offset-$last/$total',
      },
      body: chunk,
    );
    if (resp.statusCode != 200) {
      throw HttpException('upload chunk failed ${resp.statusCode}');
    }
  }

  void clearCompletedTransfers() {
    _transfers.removeWhere((t) =>
        t.state == FileTransferState.completed ||
        t.state == FileTransferState.canceled);
    notifyListeners();
  }

  void _bumpSpeed(FileTransferTask task, double bps) {
    if (bps > 0) {
      task.instantBytesPerSec = bps;
    }
    task.updatedAt = DateTime.now();
    notifyListeners();
  }

  void _ensure() {
    if (!_connected || _baseUrl == null || _fsToken == null) {
      throw StateError('Not connected');
    }
  }

  /// Утилита: соединить два пути в стиле удалённой ФС.
  static String joinRemote(String base, String name, {bool isWindows = false}) {
    if (base.isEmpty) return name;
    final sep = isWindows ? '\\' : '/';
    if (base.endsWith('/') || base.endsWith('\\')) return '$base$name';
    return '$base$sep$name';
  }

  /// Проверка/построение локального path.
  static String joinLocal(String base, String name) => p.join(base, name);

  @override
  void dispose() {
    _http.close();
    super.dispose();
  }
}

class _SpeedTicker {
  DateTime _lastTime = DateTime.now();
  int _accum = 0;

  double tick(int bytes) {
    _accum += bytes;
    final now = DateTime.now();
    final ms = now.difference(_lastTime).inMilliseconds;
    if (ms < 250) return 0;
    final bps = _accum * 1000 / ms;
    _lastTime = now;
    _accum = 0;
    return bps;
  }
}
