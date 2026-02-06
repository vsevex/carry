import 'package:flutter_test/flutter_test.dart';

import 'package:carry/carry.dart';

void main() {
  group('Origin', () {
    test('fromJson parses local', () {
      expect(Origin.fromJson('local'), equals(Origin.local));
    });

    test('fromJson parses remote', () {
      expect(Origin.fromJson('remote'), equals(Origin.remote));
    });

    test('fromJson is case insensitive', () {
      expect(Origin.fromJson('LOCAL'), equals(Origin.local));
      expect(Origin.fromJson('REMOTE'), equals(Origin.remote));
      expect(Origin.fromJson('Local'), equals(Origin.local));
    });

    test('toJson returns lowercase string', () {
      expect(Origin.local.toJson(), equals('local'));
      expect(Origin.remote.toJson(), equals('remote'));
    });

    test('round-trip serialization', () {
      for (final origin in Origin.values) {
        final json = origin.toJson();
        final restored = Origin.fromJson(json);
        expect(restored, equals(origin));
      }
    });
  });

  group('Metadata', () {
    test('creates with all fields', () {
      final metadata = Metadata(
        createdAt: 1000,
        updatedAt: 2000,
        origin: Origin.local,
        clock: const LogicalClock(nodeId: 'node1', counter: 5),
      );

      expect(metadata.createdAt, equals(1000));
      expect(metadata.updatedAt, equals(2000));
      expect(metadata.origin, equals(Origin.local));
      expect(metadata.clock.nodeId, equals('node1'));
    });

    test('fromJson parses correctly', () {
      final json = {
        'createdAt': 1500,
        'updatedAt': 2500,
        'origin': 'remote',
        'clock': {'nodeId': 'device_x', 'counter': 10},
      };

      final metadata = Metadata.fromJson(json);

      expect(metadata.createdAt, equals(1500));
      expect(metadata.updatedAt, equals(2500));
      expect(metadata.origin, equals(Origin.remote));
      expect(metadata.clock.nodeId, equals('device_x'));
      expect(metadata.clock.counter, equals(10));
    });

    test('toJson serializes correctly', () {
      final metadata = Metadata(
        createdAt: 3000,
        updatedAt: 4000,
        origin: Origin.local,
        clock: const LogicalClock(nodeId: 'n', counter: 1),
      );

      final json = metadata.toJson();

      expect(json['createdAt'], equals(3000));
      expect(json['updatedAt'], equals(4000));
      expect(json['origin'], equals('local'));
      expect(json['clock']['nodeId'], equals('n'));
    });

    test('round-trip serialization preserves data', () {
      final original = Metadata(
        createdAt: 5000,
        updatedAt: 6000,
        origin: Origin.remote,
        clock: const LogicalClock(nodeId: 'rt_node', counter: 99),
      );

      final json = original.toJson();
      final restored = Metadata.fromJson(json);

      expect(restored.createdAt, equals(original.createdAt));
      expect(restored.updatedAt, equals(original.updatedAt));
      expect(restored.origin, equals(original.origin));
      expect(restored.clock, equals(original.clock));
    });
  });

  group('Record', () {
    Metadata createMetadata({
      int createdAt = 1000,
      int updatedAt = 1000,
      Origin origin = Origin.local,
    }) {
      return Metadata(
        createdAt: createdAt,
        updatedAt: updatedAt,
        origin: origin,
        clock: const LogicalClock(nodeId: 'test_node', counter: 1),
      );
    }

    test('creates with all fields', () {
      final record = Record(
        id: 'user_1',
        collection: 'users',
        version: 1,
        payload: {'name': 'Alice', 'email': 'alice@example.com'},
        metadata: createMetadata(),
        deleted: false,
      );

      expect(record.id, equals('user_1'));
      expect(record.collection, equals('users'));
      expect(record.version, equals(1));
      expect(record.payload['name'], equals('Alice'));
      expect(record.deleted, isFalse);
    });

    test('fromJson parses correctly', () {
      final json = {
        'id': 'post_123',
        'collection': 'posts',
        'version': 3,
        'payload': {'title': 'Hello World'},
        'metadata': {
          'createdAt': 2000,
          'updatedAt': 3000,
          'origin': 'remote',
          'clock': {'nodeId': 'server', 'counter': 50},
        },
        'deleted': false,
      };

      final record = Record.fromJson(json);

      expect(record.id, equals('post_123'));
      expect(record.collection, equals('posts'));
      expect(record.version, equals(3));
      expect(record.payload['title'], equals('Hello World'));
      expect(record.metadata.origin, equals(Origin.remote));
      expect(record.deleted, isFalse);
    });

    test('toJson serializes correctly', () {
      final record = Record(
        id: 'item_1',
        collection: 'items',
        version: 2,
        payload: {'data': 'test'},
        metadata: createMetadata(updatedAt: 2000),
        deleted: false,
      );

      final json = record.toJson();

      expect(json['id'], equals('item_1'));
      expect(json['collection'], equals('items'));
      expect(json['version'], equals(2));
      expect(json['payload'], equals({'data': 'test'}));
      expect(json['deleted'], isFalse);
      expect(json['metadata'], isA<Map>());
    });

    test('round-trip serialization preserves data', () {
      final original = Record(
        id: 'roundtrip_1',
        collection: 'test_collection',
        version: 5,
        payload: {
          'nested': {
            'array': [1, 2, 3],
            'bool': true,
          },
        },
        metadata: createMetadata(
          createdAt: 100,
          updatedAt: 200,
          origin: Origin.remote,
        ),
        deleted: true,
      );

      final json = original.toJson();
      final restored = Record.fromJson(json);

      expect(restored.id, equals(original.id));
      expect(restored.collection, equals(original.collection));
      expect(restored.version, equals(original.version));
      expect(restored.payload, equals(original.payload));
      expect(restored.deleted, equals(original.deleted));
    });

    test('isActive returns true when not deleted', () {
      final record = Record(
        id: '1',
        collection: 'test',
        version: 1,
        payload: {},
        metadata: createMetadata(),
        deleted: false,
      );

      expect(record.isActive, isTrue);
    });

    test('isActive returns false when deleted', () {
      final record = Record(
        id: '2',
        collection: 'test',
        version: 1,
        payload: {},
        metadata: createMetadata(),
        deleted: true,
      );

      expect(record.isActive, isFalse);
    });

    test('createdAt getter returns metadata value', () {
      final record = Record(
        id: '3',
        collection: 'test',
        version: 1,
        payload: {},
        metadata: createMetadata(createdAt: 9999),
        deleted: false,
      );

      expect(record.createdAt, equals(9999));
    });

    test('updatedAt getter returns metadata value', () {
      final record = Record(
        id: '4',
        collection: 'test',
        version: 1,
        payload: {},
        metadata: createMetadata(updatedAt: 8888),
        deleted: false,
      );

      expect(record.updatedAt, equals(8888));
    });

    test('toString formats correctly for active record', () {
      final record = Record(
        id: 'rec_id',
        collection: 'my_collection',
        version: 7,
        payload: {},
        metadata: createMetadata(),
        deleted: false,
      );

      expect(record.toString(), equals('Record(my_collection/rec_id v7)'));
    });

    test('toString includes deleted marker for deleted record', () {
      final record = Record(
        id: 'deleted_rec',
        collection: 'trash',
        version: 2,
        payload: {},
        metadata: createMetadata(),
        deleted: true,
      );

      expect(record.toString(), contains('[deleted]'));
      expect(
        record.toString(),
        equals('Record(trash/deleted_rec v2 [deleted])'),
      );
    });

    test('equality based on id, collection, and version', () {
      final record1 = Record(
        id: 'same_id',
        collection: 'same_col',
        version: 1,
        payload: {'different': 'payload'},
        metadata: createMetadata(createdAt: 100),
        deleted: false,
      );

      final record2 = Record(
        id: 'same_id',
        collection: 'same_col',
        version: 1,
        payload: {'other': 'data'},
        metadata: createMetadata(createdAt: 200),
        deleted: true,
      );

      expect(record1 == record2, isTrue);
      expect(record1.hashCode, equals(record2.hashCode));
    });

    test('inequality when id differs', () {
      final record1 = Record(
        id: 'id_1',
        collection: 'col',
        version: 1,
        payload: {},
        metadata: createMetadata(),
        deleted: false,
      );

      final record2 = Record(
        id: 'id_2',
        collection: 'col',
        version: 1,
        payload: {},
        metadata: createMetadata(),
        deleted: false,
      );

      expect(record1 == record2, isFalse);
    });

    test('inequality when collection differs', () {
      final record1 = Record(
        id: 'id',
        collection: 'col_1',
        version: 1,
        payload: {},
        metadata: createMetadata(),
        deleted: false,
      );

      final record2 = Record(
        id: 'id',
        collection: 'col_2',
        version: 1,
        payload: {},
        metadata: createMetadata(),
        deleted: false,
      );

      expect(record1 == record2, isFalse);
    });

    test('inequality when version differs', () {
      final record1 = Record(
        id: 'id',
        collection: 'col',
        version: 1,
        payload: {},
        metadata: createMetadata(),
        deleted: false,
      );

      final record2 = Record(
        id: 'id',
        collection: 'col',
        version: 2,
        payload: {},
        metadata: createMetadata(),
        deleted: false,
      );

      expect(record1 == record2, isFalse);
    });

    test('handles empty payload', () {
      final record = Record(
        id: 'empty',
        collection: 'test',
        version: 1,
        payload: {},
        metadata: createMetadata(),
        deleted: false,
      );

      expect(record.payload, isEmpty);

      final json = record.toJson();
      final restored = Record.fromJson(json);
      expect(restored.payload, isEmpty);
    });

    test('handles complex nested payload', () {
      final complexPayload = {
        'string': 'text',
        'number': 42,
        'float': 3.14,
        'bool': true,
        'null': null,
        'array': [1, 'two', 3.0, false],
        'nested': {
          'level1': {
            'level2': {'value': 'deep'},
          },
        },
      };

      final record = Record(
        id: 'complex',
        collection: 'test',
        version: 1,
        payload: complexPayload,
        metadata: createMetadata(),
        deleted: false,
      );

      final json = record.toJson();
      final restored = Record.fromJson(json);

      expect(restored.payload, equals(complexPayload));
    });
  });
}
