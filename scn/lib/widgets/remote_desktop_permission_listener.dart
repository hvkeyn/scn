import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:scn/models/remote_desktop_models.dart';
import 'package:scn/services/remote_desktop/remote_desktop_host_service.dart';
import 'package:scn/widgets/remote_desktop_permission_dialog.dart';

/// Подписывается на стрим запросов от RD host и показывает диалог поверх UI.
class RemoteDesktopPermissionListener extends StatefulWidget {
  final Widget child;
  const RemoteDesktopPermissionListener({super.key, required this.child});

  @override
  State<RemoteDesktopPermissionListener> createState() =>
      _RemoteDesktopPermissionListenerState();
}

class _RemoteDesktopPermissionListenerState
    extends State<RemoteDesktopPermissionListener> {
  StreamSubscription<RemoteDesktopPermissionRequest>? _sub;
  RemoteDesktopHostService? _hostService;
  bool _dialogVisible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final svc = context.read<RemoteDesktopHostService>();
    if (svc != _hostService) {
      _hostService = svc;
      _sub?.cancel();
      _sub = svc.approvalRequests.listen(_handleRequest);
    }
  }

  Future<void> _handleRequest(RemoteDesktopPermissionRequest req) async {
    if (_dialogVisible || !mounted) return;
    _dialogVisible = true;
    try {
      final approved =
          await RemoteDesktopPermissionDialog.show(context, req);
      _hostService?.respondToApproval(req.sessionId, approved);
    } finally {
      _dialogVisible = false;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
