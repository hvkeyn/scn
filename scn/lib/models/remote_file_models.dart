import 'package:flutter/foundation.dart';

/// Тип записи в удалённой / локальной ФС.
enum RemoteFileEntryType { directory, file, symlink, drive, other }

/// Одна запись файлового менеджера (файл, папка, диск).
class RemoteFileEntry {
  final String name;
  final String path; // абсолютный путь внутри удалённой/локальной ФС
  final RemoteFileEntryType type;
  final int size; // 0 для каталогов
  final DateTime? modified;
  final bool isHidden;
  final bool readOnly;

  const RemoteFileEntry({
    required this.name,
    required this.path,
    required this.type,
    this.size = 0,
    this.modified,
    this.isHidden = false,
    this.readOnly = false,
  });

  bool get isDirectory =>
      type == RemoteFileEntryType.directory ||
      type == RemoteFileEntryType.drive;

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'type': type.name,
        'size': size,
        if (modified != null) 'modified': modified!.toIso8601String(),
        'isHidden': isHidden,
        'readOnly': readOnly,
      };

  factory RemoteFileEntry.fromJson(Map<String, dynamic> json) {
    final t = json['type'] as String? ?? 'file';
    return RemoteFileEntry(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      type: RemoteFileEntryType.values.firstWhere(
        (e) => e.name == t,
        orElse: () => RemoteFileEntryType.other,
      ),
      size: (json['size'] as num?)?.toInt() ?? 0,
      modified: json['modified'] != null
          ? DateTime.tryParse(json['modified'] as String)
          : null,
      isHidden: json['isHidden'] as bool? ?? false,
      readOnly: json['readOnly'] as bool? ?? false,
    );
  }
}

/// Содержимое директории + контекст.
class RemoteFileListing {
  final String path;
  final String? parentPath;
  final List<RemoteFileEntry> entries;

  const RemoteFileListing({
    required this.path,
    required this.parentPath,
    required this.entries,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'parentPath': parentPath,
        'entries': entries.map((e) => e.toJson()).toList(),
      };

  factory RemoteFileListing.fromJson(Map<String, dynamic> json) {
    final list = (json['entries'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(RemoteFileEntry.fromJson)
        .toList();
    return RemoteFileListing(
      path: json['path'] as String? ?? '',
      parentPath: json['parentPath'] as String?,
      entries: list,
    );
  }
}

/// Состояние одной операции переноса (upload или download).
enum FileTransferDirection { upload, download }

enum FileTransferState {
  queued,
  preparing,
  inProgress,
  completed,
  failed,
  canceled,
  paused,
}

class FileTransferTask {
  final String id;
  final String sourcePath;
  final String destPath;
  final FileTransferDirection direction;
  final int totalBytes;

  int transferredBytes;
  FileTransferState state;
  String? errorMessage;
  double instantBytesPerSec;
  DateTime startedAt;
  DateTime updatedAt;

  FileTransferTask({
    required this.id,
    required this.sourcePath,
    required this.destPath,
    required this.direction,
    required this.totalBytes,
    this.transferredBytes = 0,
    this.state = FileTransferState.queued,
    this.errorMessage,
    this.instantBytesPerSec = 0,
    DateTime? startedAt,
    DateTime? updatedAt,
  })  : startedAt = startedAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  double get progress {
    if (totalBytes <= 0) return 0;
    return (transferredBytes / totalBytes).clamp(0.0, 1.0);
  }

  bool get isTerminal =>
      state == FileTransferState.completed ||
      state == FileTransferState.failed ||
      state == FileTransferState.canceled;
}

/// Параметры подключения к удалённой ФС.
@immutable
class RemoteFileSessionParams {
  final String host;
  final int port;
  final String? password;
  final String viewerDeviceId;
  final String viewerAlias;

  const RemoteFileSessionParams({
    required this.host,
    required this.port,
    required this.viewerDeviceId,
    required this.viewerAlias,
    this.password,
  });
}

/// Ответ при connect к файловой системе хоста.
class RemoteFileSessionGrant {
  final String fsToken;
  final String sessionId;
  final List<RemoteFileEntry> roots;
  final bool readOnly;

  const RemoteFileSessionGrant({
    required this.fsToken,
    required this.sessionId,
    required this.roots,
    required this.readOnly,
  });

  Map<String, dynamic> toJson() => {
        'fsToken': fsToken,
        'sessionId': sessionId,
        'readOnly': readOnly,
        'roots': roots.map((e) => e.toJson()).toList(),
      };

  factory RemoteFileSessionGrant.fromJson(Map<String, dynamic> json) {
    final r = (json['roots'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(RemoteFileEntry.fromJson)
        .toList();
    return RemoteFileSessionGrant(
      fsToken: json['fsToken'] as String? ?? '',
      sessionId: json['sessionId'] as String? ?? '',
      readOnly: json['readOnly'] as bool? ?? false,
      roots: r,
    );
  }
}
