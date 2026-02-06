import 'package:flutter/material.dart';

import '../carry_devtools_extension.dart';

/// Panel showing sync status and history.
class SyncStatusPanel extends StatelessWidget {
  const SyncStatusPanel({
    super.key,
    required this.debugInfo,
  });

  final CarryDebugInfo debugInfo;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusCards(context),
            const SizedBox(height: 24),
            Text(
              'Sync History',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _buildSyncHistory(context),
            ),
          ],
        ),
      );

  Widget _buildStatusCards(BuildContext context) => Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          _StatusCard(
            title: 'Pending Operations',
            value: debugInfo.pendingCount.toString(),
            icon: Icons.pending_actions,
            color: debugInfo.pendingCount > 0 ? Colors.orange : Colors.green,
          ),
          _StatusCard(
            title: 'Total Syncs',
            value: debugInfo.syncHistory.length.toString(),
            icon: Icons.history,
            color: Colors.blue,
          ),
          _StatusCard(
            title: 'Total Conflicts',
            value: debugInfo.conflictHistory.length.toString(),
            icon: Icons.warning_amber,
            color: debugInfo.conflictHistory.isNotEmpty
                ? Colors.amber
                : Colors.grey,
          ),
          _StatusCard(
            title: 'Collections',
            value: debugInfo.collections.length.toString(),
            icon: Icons.folder,
            color: Colors.purple,
          ),
        ],
      );

  Widget _buildSyncHistory(BuildContext context) {
    if (debugInfo.syncHistory.isEmpty) {
      return const Center(
        child: Text(
          'No sync history yet',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      itemCount: debugInfo.syncHistory.length,
      itemBuilder: (context, index) {
        final entry = debugInfo.syncHistory[index];
        final success = entry['success'] as bool? ?? false;
        final timestamp = entry['timestamp'] as String? ?? '';
        final pushedCount = entry['pushedCount'] as int? ?? 0;
        final pulledCount = entry['pulledCount'] as int? ?? 0;
        final conflictCount = entry['conflictCount'] as int? ?? 0;
        final durationMs = entry['durationMs'] as int?;
        final error = entry['error'] as String?;

        return Card(
          child: ListTile(
            leading: Icon(
              success ? Icons.check_circle : Icons.error,
              color: success ? Colors.green : Colors.red,
            ),
            title: Row(
              children: [
                Text(success ? 'Sync Successful' : 'Sync Failed'),
                const SizedBox(width: 8),
                if (durationMs != null)
                  Chip(
                    label: Text('${durationMs}ms'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_formatTimestamp(timestamp)),
                if (success)
                  Text(
                    'Pushed: $pushedCount | Pulled: $pulledCount | Conflicts: $conflictCount',
                    style: const TextStyle(fontSize: 12),
                  ),
                if (error != null)
                  Text(
                    error,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
              ],
            ),
            isThreeLine: error != null || success,
          ),
        );
      },
    );
  }

  String _formatTimestamp(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inSeconds < 60) {
        return '${diff.inSeconds}s ago';
      } else if (diff.inMinutes < 60) {
        return '${diff.inMinutes}m ago';
      } else if (diff.inHours < 24) {
        return '${diff.inHours}h ago';
      } else {
        return '${diff.inDays}d ago';
      }
    } catch (_) {
      return isoString;
    }
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(height: 8),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
              ),
              Text(
                title,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
}
