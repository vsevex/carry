import 'package:flutter/material.dart';

/// Panel showing collection statistics.
class CollectionsPanel extends StatelessWidget {
  const CollectionsPanel({
    super.key,
    required this.collections,
    required this.schema,
  });

  final List<Map<String, dynamic>> collections;
  final Map<String, dynamic> schema;

  @override
  Widget build(BuildContext context) {
    if (collections.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No collections found',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Collections will appear after the store is initialized',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final schemaVersion = schema['version'] ?? 'unknown';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.schema, color: Colors.purple),
              const SizedBox(width: 8),
              Text(
                'Schema v$schemaVersion',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              Chip(
                label: Text('${collections.length} collections'),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 300,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.5,
            ),
            itemCount: collections.length,
            itemBuilder: (context, index) {
              final collection = collections[index];
              return _buildCollectionCard(context, collection);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCollectionCard(
    BuildContext context,
    Map<String, dynamic> collection,
  ) {
    final name = collection['name'] as String? ?? 'unknown';
    final recordCount = collection['recordCount'] as int? ?? 0;

    return Card(
      child: InkWell(
        onTap: () {
          // Could expand to show fields, etc.
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.folder,
                size: 40,
                color: Colors.purple,
              ),
              const SizedBox(height: 12),
              Text(
                name,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '$recordCount record${recordCount == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
