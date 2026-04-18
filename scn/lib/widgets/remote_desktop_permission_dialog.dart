import 'package:flutter/material.dart';

import 'package:scn/models/remote_desktop_models.dart';

/// Диалог, в котором хост соглашается / отклоняет входящий RD-запрос.
class RemoteDesktopPermissionDialog extends StatefulWidget {
  final RemoteDesktopPermissionRequest request;

  const RemoteDesktopPermissionDialog({super.key, required this.request});

  static Future<bool> show(
      BuildContext context, RemoteDesktopPermissionRequest request) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RemoteDesktopPermissionDialog(request: request),
    );
    return result ?? false;
  }

  @override
  State<RemoteDesktopPermissionDialog> createState() =>
      _RemoteDesktopPermissionDialogState();
}

class _RemoteDesktopPermissionDialogState
    extends State<RemoteDesktopPermissionDialog> {
  int _seconds = 30;
  late final Stream<int> _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Stream<int>.periodic(
        const Duration(seconds: 1), (i) => 30 - (i + 1)).take(30);
    _ticker.listen((value) {
      if (!mounted) return;
      setState(() => _seconds = value);
      if (value <= 0 && mounted) {
        Navigator.of(context).pop(false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    return AlertDialog(
      icon: const Icon(Icons.desktop_windows, size: 36),
      title: Text('Remote desktop request'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${r.viewerAlias} is asking to view your screen.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          _kv('Address', r.viewerAddress),
          _kv('Device ID', r.viewerDeviceId),
          _kv('Wants control', r.wantsControl ? 'Yes' : 'No (view-only)'),
          const SizedBox(height: 12),
          Text(
            'Auto-rejecting in $_seconds seconds.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Reject'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.check),
          label: const Text('Allow'),
        ),
      ],
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$key:',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
