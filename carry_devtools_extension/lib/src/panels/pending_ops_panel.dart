import 'package:flutter/material.dart';

/// Panel showing pending operations waiting to be synced.
class PendingOpsPanel extends StatelessWidget {
  const PendingOpsPanel({
    super.key,
    required this.pendingOps,
  });

  final List<Map<String, dynamic>> pendingOps;

  @override
  Widget build(BuildContext context) {
    if (pendingOps.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
            SizedBox(height: 16),
            Text(
              'No pending operations',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'All local changes have been synced',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.pending_actions, color: Colors.orange),
              const SizedBox(width: 8),
              Text(
                '${pendingOps.length} pending operation${pendingOps.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: pendingOps.length,
            itemBuilder: (context, index) {
              final op = pendingOps[index];
              return _buildOperationTile(context, op, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildOperationTile(
    BuildContext context,
    Map<String, dynamic> op,
    int index,
  ) {
    final opId = op['opId'] as String? ?? 'unknown';
    final recordId = op['recordId'] as String? ?? 'unknown';
    final collection = op['collection'] as String? ?? 'unknown';
    final type = op['type'] as String? ?? 'unknown';
    final timestamp = op['timestamp'] as int? ?? 0;

    IconData icon;
    Color color;
    switch (type) {
      case 'create':
        icon = Icons.add_circle;
        color = Colors.green;
        break;
      case 'update':
        icon = Icons.edit;
        color = Colors.blue;
        break;
      case 'delete':
        icon = Icons.delete;
        color = Colors.red;
        break;
      default:
        icon = Icons.help;
        color = Colors.grey;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ExpansionTile(
        leading: Icon(icon, color: color),
        title: Text('${type.toUpperCase()} on $collection'),
        subtitle: Text('Record: $recordId'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow(label: 'Operation ID', value: opId),
                _DetailRow(label: 'Record ID', value: recordId),
                _DetailRow(label: 'Collection', value: collection),
                _DetailRow(label: 'Type', value: type),
                _DetailRow(
                  label: 'Timestamp',
                  value: _formatTimestamp(timestamp),
                ),
                _DetailRow(label: 'Queue Position', value: '#${index + 1}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(int timestamp) {
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
      return dt.toIso8601String();
    } catch (_) {
      return timestamp.toString();
    }
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
            Expanded(
              child: SelectableText(
                value,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
      );
}
