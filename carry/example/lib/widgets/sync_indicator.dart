import 'package:carry/carry.dart';

import 'package:flutter/material.dart';

/// A small indicator showing WebSocket connection status.
class SyncIndicator extends StatelessWidget {
  const SyncIndicator({required this.state, super.key});

  final WebSocketConnectionState state;

  @override
  Widget build(BuildContext context) {
    final (color, icon, tooltip) = switch (state) {
      WebSocketConnectionState.connected => (
          Colors.green,
          Icons.cloud_done_outlined,
          'Connected'
        ),
      WebSocketConnectionState.connecting => (
          Colors.orange,
          Icons.cloud_upload_outlined,
          'Connecting...'
        ),
      WebSocketConnectionState.reconnecting => (
          Colors.orange,
          Icons.cloud_sync_outlined,
          'Reconnecting...'
        ),
      WebSocketConnectionState.disconnected => (
          Colors.red,
          Icons.cloud_off_outlined,
          'Offline'
        ),
    };

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
