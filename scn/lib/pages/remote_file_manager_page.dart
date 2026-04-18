import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:scn/models/remote_file_models.dart';
import 'package:scn/services/remote_desktop/remote_file_client_service.dart';

/// Двухпанельный файловый менеджер а-ля Total Commander.
/// Левая панель — локальная ФС, правая — удалённая (поверх RemoteFileClientService).
class RemoteFileManagerPage extends StatefulWidget {
  final RemoteFileSessionParams params;
  final String title;

  const RemoteFileManagerPage({
    super.key,
    required this.params,
    this.title = 'Remote files',
  });

  @override
  State<RemoteFileManagerPage> createState() => _RemoteFileManagerPageState();
}

class _RemoteFileManagerPageState extends State<RemoteFileManagerPage> {
  final RemoteFileClientService _client = RemoteFileClientService();

  bool _connecting = true;
  String? _error;

  // Локальная панель
  String _localPath = '';
  List<RemoteFileEntry> _localEntries = const [];
  final Set<String> _localSelected = <String>{};
  String? _localParent;

  // Удалённая панель
  List<RemoteFileEntry> _remoteRoots = const [];
  String _remotePath = '';
  List<RemoteFileEntry> _remoteEntries = const [];
  final Set<String> _remoteSelected = <String>{};
  String? _remoteParent;

  bool _activeRightPane = true; // последняя активная панель

  @override
  void initState() {
    super.initState();
    _client.addListener(_onClientChange);
    _connect();
  }

  Future<void> _connect() async {
    try {
      final grant = await _client.connect(widget.params);
      _remoteRoots = grant.roots;
      // открываем первый корень по умолчанию
      if (grant.roots.isNotEmpty) {
        await _openRemote(grant.roots.first.path);
      }
      // локально — Documents/Home
      final localStart = await _defaultLocalRoot();
      await _openLocal(localStart);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _connecting = false;
        });
      }
    }
  }

  Future<String> _defaultLocalRoot() async {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    return home;
  }

  void _onClientChange() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _client.removeListener(_onClientChange);
    _client.disconnect();
    _client.dispose();
    super.dispose();
  }

  // ---------------- Local FS ----------------

  Future<void> _openLocal(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) return;
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
        } catch (_) {}
      }
      entries.sort(_sortEntries);
      final parent = p.dirname(path);
      setState(() {
        _localPath = path;
        _localEntries = entries;
        _localParent = (parent == path || parent.isEmpty) ? null : parent;
        _localSelected.clear();
      });
    } catch (e) {
      _showSnack('Local error: $e');
    }
  }

  // ---------------- Remote FS ----------------

  Future<void> _openRemote(String path) async {
    try {
      final listing = await _client.list(path);
      setState(() {
        _remotePath = listing.path;
        _remoteEntries = listing.entries;
        _remoteParent = listing.parentPath;
        _remoteSelected.clear();
      });
    } catch (e) {
      _showSnack('Remote error: $e');
    }
  }

  // ---------------- helpers ----------------

  int _sortEntries(RemoteFileEntry a, RemoteFileEntry b) {
    if (a.isDirectory != b.isDirectory) {
      return a.isDirectory ? -1 : 1;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------- transfer actions ----------------

  Future<void> _copyLocalToRemote() async {
    if (_client.isReadOnly) {
      _showSnack('Remote is read-only');
      return;
    }
    if (_localSelected.isEmpty || _remotePath.isEmpty) return;
    for (final src in _localSelected.toList()) {
      final entry = _localEntries.firstWhere((e) => e.path == src);
      if (entry.isDirectory) {
        _showSnack('Directories upload not yet supported (${entry.name})');
        continue;
      }
      final dest = RemoteFileClientService.joinRemote(
          _remotePath, entry.name, isWindows: _remotePath.contains('\\'));
      try {
        await _client.uploadFile(localPath: src, remotePath: dest);
      } catch (e) {
        _showSnack('Upload failed: $e');
      }
    }
    await _openRemote(_remotePath);
  }

  Future<void> _copyRemoteToLocal() async {
    if (_remoteSelected.isEmpty || _localPath.isEmpty) return;
    for (final src in _remoteSelected.toList()) {
      final entry = _remoteEntries.firstWhere((e) => e.path == src);
      if (entry.isDirectory) {
        _showSnack('Directories download not yet supported (${entry.name})');
        continue;
      }
      final dest = RemoteFileClientService.joinLocal(_localPath, entry.name);
      try {
        await _client.downloadFile(
          remotePath: src,
          localPath: dest,
          remoteSize: entry.size,
        );
      } catch (e) {
        _showSnack('Download failed: $e');
      }
    }
    await _openLocal(_localPath);
  }

  Future<void> _deleteSelected({required bool remote}) async {
    final selected = remote ? _remoteSelected : _localSelected;
    if (selected.isEmpty) return;
    final ok = await _confirm(
        'Delete ${selected.length} item(s) on ${remote ? 'remote' : 'local'}?');
    if (!ok) return;
    if (remote) {
      if (_client.isReadOnly) {
        _showSnack('Remote is read-only');
        return;
      }
      for (final path in selected.toList()) {
        try {
          await _client.delete(path);
        } catch (e) {
          _showSnack('Delete failed: $e');
        }
      }
      await _openRemote(_remotePath);
    } else {
      for (final path in selected.toList()) {
        try {
          final type = await FileSystemEntity.type(path);
          if (type == FileSystemEntityType.directory) {
            await Directory(path).delete(recursive: true);
          } else {
            await File(path).delete();
          }
        } catch (e) {
          _showSnack('Delete failed: $e');
        }
      }
      await _openLocal(_localPath);
    }
  }

  Future<void> _mkdir({required bool remote}) async {
    final name = await _promptText('New folder name', '');
    if (name == null || name.trim().isEmpty) return;
    if (remote) {
      if (_client.isReadOnly) {
        _showSnack('Remote is read-only');
        return;
      }
      final dest = RemoteFileClientService.joinRemote(
          _remotePath, name.trim(),
          isWindows: _remotePath.contains('\\'));
      try {
        await _client.mkdir(dest);
        await _openRemote(_remotePath);
      } catch (e) {
        _showSnack('Mkdir failed: $e');
      }
    } else {
      try {
        await Directory(p.join(_localPath, name.trim())).create();
        await _openLocal(_localPath);
      } catch (e) {
        _showSnack('Mkdir failed: $e');
      }
    }
  }

  Future<void> _renameSelected({required bool remote}) async {
    final selected = remote ? _remoteSelected : _localSelected;
    if (selected.length != 1) {
      _showSnack('Select exactly one item to rename');
      return;
    }
    final src = selected.first;
    final base = p.basename(src);
    final newName = await _promptText('Rename to', base);
    if (newName == null || newName.trim().isEmpty || newName == base) return;
    final dir = p.dirname(src);
    final dest = remote
        ? RemoteFileClientService.joinRemote(dir, newName.trim(),
            isWindows: src.contains('\\'))
        : p.join(dir, newName.trim());
    try {
      if (remote) {
        if (_client.isReadOnly) {
          _showSnack('Remote is read-only');
          return;
        }
        await _client.rename(src, dest);
        await _openRemote(_remotePath);
      } else {
        await FileSystemEntity.type(src) == FileSystemEntityType.directory
            ? await Directory(src).rename(dest)
            : await File(src).rename(dest);
        await _openLocal(_localPath);
      }
    } catch (e) {
      _showSnack('Rename failed: $e');
    }
  }

  Future<void> _addLocalFromPicker() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result == null) return;
      // выберем эти файлы в "локальной" панели через копирование путей в текущую папку
      // Просто открываем папку, где они лежат, и преселектим имена.
      if (result.files.isEmpty) return;
      final firstDir = p.dirname(result.files.first.path ?? '');
      if (firstDir.isEmpty) return;
      await _openLocal(firstDir);
      setState(() {
        _localSelected.clear();
        for (final f in result.files) {
          if (f.path != null) _localSelected.add(f.path!);
        }
      });
    } catch (e) {
      _showSnack('Picker failed: $e');
    }
  }

  Future<bool> _confirm(String text) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm'),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  Future<String?> _promptText(String title, String initial) async {
    final ctrl = TextEditingController(text: initial);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('OK')),
        ],
      ),
    );
    return res;
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              if (_localPath.isNotEmpty) await _openLocal(_localPath);
              if (_remotePath.isNotEmpty) await _openRemote(_remotePath);
            },
          ),
          IconButton(
            tooltip: 'Disconnect',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _client.disconnect();
              if (mounted) Navigator.of(context).maybePop();
            },
          ),
        ],
      ),
      body: _connecting
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.redAccent, size: 48),
                        const SizedBox(height: 12),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.redAccent)),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ),
                )
              : _buildPanels(),
    );
  }

  Widget _buildPanels() {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildPane(remote: false)),
              const VerticalDivider(width: 1),
              Expanded(child: _buildPane(remote: true)),
            ],
          ),
        ),
        const Divider(height: 1),
        _buildActionBar(),
        const Divider(height: 1),
        SizedBox(height: 140, child: _buildTransfersPanel()),
      ],
    );
  }

  Widget _buildPane({required bool remote}) {
    final entries = remote ? _remoteEntries : _localEntries;
    final path = remote ? _remotePath : _localPath;
    final parent = remote ? _remoteParent : _localParent;
    final selected = remote ? _remoteSelected : _localSelected;
    final theme = Theme.of(context);
    final highlight = _activeRightPane == remote
        ? theme.colorScheme.primary.withOpacity(0.15)
        : Colors.transparent;
    return GestureDetector(
      onTap: () => setState(() => _activeRightPane = remote),
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: highlight,
        child: Column(
          children: [
            _buildPathBar(remote: remote, path: path, parent: parent),
            const Divider(height: 1),
            if (remote && _remoteRoots.isNotEmpty)
              SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  children: [
                    for (final root in _remoteRoots)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ActionChip(
                          label: Text(root.name),
                          onPressed: () => _openRemote(root.path),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: entries.length + (parent != null ? 1 : 0),
                itemBuilder: (ctx, idx) {
                  if (parent != null && idx == 0) {
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.subdirectory_arrow_left),
                      title: const Text('..'),
                      onTap: () =>
                          remote ? _openRemote(parent) : _openLocal(parent),
                    );
                  }
                  final entry =
                      entries[idx - (parent != null ? 1 : 0)];
                  final isSelected = selected.contains(entry.path);
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      entry.type == RemoteFileEntryType.drive
                          ? Icons.storage
                          : entry.isDirectory
                              ? Icons.folder
                              : Icons.insert_drive_file_outlined,
                      color: entry.isDirectory ? Colors.amber : null,
                    ),
                    title: Text(entry.name,
                        overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      entry.isDirectory
                          ? '<DIR>'
                          : '${_formatSize(entry.size)}'
                              '${entry.modified != null ? '  ·  ${_formatDate(entry.modified!)}' : ''}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    selected: isSelected,
                    selectedTileColor:
                        theme.colorScheme.primary.withOpacity(0.18),
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          selected.remove(entry.path);
                        } else {
                          selected.add(entry.path);
                        }
                        _activeRightPane = remote;
                      });
                    },
                    onLongPress: () {
                      if (entry.isDirectory) {
                        if (remote) {
                          _openRemote(entry.path);
                        } else {
                          _openLocal(entry.path);
                        }
                      }
                    },
                    trailing: entry.isDirectory
                        ? IconButton(
                            icon: const Icon(Icons.chevron_right),
                            onPressed: () => remote
                                ? _openRemote(entry.path)
                                : _openLocal(entry.path),
                          )
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPathBar(
      {required bool remote, required String path, required String? parent}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Icon(remote ? Icons.cloud_outlined : Icons.computer,
              size: 18, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              path.isEmpty ? '(none)' : path,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (parent != null)
            IconButton(
              tooltip: 'Up',
              icon: const Icon(Icons.arrow_upward, size: 18),
              onPressed: () =>
                  remote ? _openRemote(parent) : _openLocal(parent),
            ),
          IconButton(
            tooltip: 'New folder',
            icon: const Icon(Icons.create_new_folder_outlined, size: 18),
            onPressed: () => _mkdir(remote: remote),
          ),
          if (!remote)
            IconButton(
              tooltip: 'Pick local files',
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              onPressed: _addLocalFromPicker,
            ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ElevatedButton.icon(
            icon: const Icon(Icons.east, size: 16),
            label: const Text('Local → Remote'),
            onPressed:
                _localSelected.isEmpty ? null : _copyLocalToRemote,
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.west, size: 16),
            label: const Text('Remote → Local'),
            onPressed:
                _remoteSelected.isEmpty ? null : _copyRemoteToLocal,
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.drive_file_rename_outline, size: 16),
            label: const Text('Rename'),
            onPressed: () =>
                _renameSelected(remote: _activeRightPane),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Delete'),
            onPressed: () => _deleteSelected(remote: _activeRightPane),
          ),
        ],
      ),
    );
  }

  Widget _buildTransfersPanel() {
    final transfers = _client.transfers;
    if (transfers.isEmpty) {
      return const Center(
        child: Text('No active transfers',
            style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.separated(
      itemCount: transfers.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, idx) {
        final t = transfers[idx];
        Color color;
        switch (t.state) {
          case FileTransferState.completed:
            color = Colors.green;
            break;
          case FileTransferState.failed:
            color = Colors.redAccent;
            break;
          case FileTransferState.canceled:
            color = Colors.grey;
            break;
          default:
            color = Colors.blue;
        }
        return ListTile(
          dense: true,
          leading: Icon(
            t.direction == FileTransferDirection.upload
                ? Icons.upload
                : Icons.download,
            color: color,
          ),
          title: Text(p.basename(t.sourcePath),
              overflow: TextOverflow.ellipsis),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(
                value: t.totalBytes > 0 ? t.progress : null,
                color: color,
                minHeight: 4,
              ),
              const SizedBox(height: 4),
              Text(
                '${t.state.name} · '
                '${_formatSize(t.transferredBytes)}/'
                '${_formatSize(t.totalBytes)} · '
                '${_formatSize(t.instantBytesPerSec.round())}/s'
                '${t.errorMessage != null ? '  ·  ${t.errorMessage}' : ''}',
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes} B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  String _formatDate(DateTime dt) {
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }
}
