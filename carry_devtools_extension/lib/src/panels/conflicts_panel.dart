import 'package:flutter/material.dart';

/// Panel showing conflict history.
class ConflictsPanel extends StatelessWidget {
  const ConflictsPanel({
    super.key,
    required this.conflicts,
  });

  final List<Map<String, dynamic>> conflicts;

  @override
  Widget build(BuildContext context) {
    if (conflicts.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
            SizedBox(height: 16),
            Text(
              'No conflicts recorded',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Conflicts will appear here when they occur during sync',
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
              const Icon(Icons.warning_amber, color: Colors.amber),
              const SizedBox(width: 8),
              Text(
                '${conflicts.length} conflict${conflicts.length == 1 ? '' : 's'} resolved',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: conflicts.length,
            itemBuilder: (context, index) {
              final conflict = conflicts[index];
              return _buildConflictTile(context, conflict);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildConflictTile(
    BuildContext context,
    Map<String, dynamic> conflict,
  ) {
    final timestamp = conflict['timestamp'] as String? ?? '';
    final recordId = conflict['recordId'] as String? ?? 'unknown';
    final collection = conflict['collection'] as String? ?? 'unknown';
    final localOpId = conflict['localOpId'] as String? ?? 'unknown';
    final remoteOpId = conflict['remoteOpId'] as String? ?? 'unknown';
    final winnerId = conflict['winnerId'] as String? ?? 'unknown';
    final resolution = conflict['resolution'] as String? ?? 'unknown';

    final localWon = winnerId == localOpId;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ExpansionTile(
        leading: Icon(
          Icons.compare_arrows,
          color: localWon ? Colors.green : Colors.orange,
        ),
        title: Text('Conflict in $collection'),
        subtitle: Text(
          'Record: $recordId - ${localWon ? 'Local won' : 'Remote won'}',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ConflictDetailRow(
                  label: 'Time',
                  value: _formatTimestamp(timestamp),
                ),
                _ConflictDetailRow(label: 'Collection', value: collection),
                _ConflictDetailRow(label: 'Record ID', value: recordId),
                const Divider(),
                _ConflictDetailRow(
                  label: 'Local Op',
                  value: localOpId,
                  highlight: localWon,
                ),
                _ConflictDetailRow(
                  label: 'Remote Op',
                  value: remoteOpId,
                  highlight: !localWon,
                ),
                const Divider(),
                _ConflictDetailRow(
                  label: 'Resolution',
                  value: resolution,
                ),
                _ConflictDetailRow(
                  label: 'Winner',
                  value: winnerId,
                  highlight: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoString;
    }
  }
}

class _ConflictDetailRow extends StatelessWidget {
  const _ConflictDetailRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
            Expanded(
              child: Container(
                padding: highlight
                    ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
                    : null,
                decoration: highlight
                    ? BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      )
                    : null,
                child: SelectableText(
                  value,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: highlight ? Colors.green : null,
                    fontWeight: highlight ? FontWeight.bold : null,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}
