/// Main test file that imports all test suites.
///
/// This file serves as an entry point and also contains integration-style
/// tests that verify components work together.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:carry/carry.dart';

// Import individual test files
import 'schema_test.dart' as schema_test;
import 'clock_test.dart' as clock_test;
import 'operation_test.dart' as operation_test;
import 'record_test.dart' as record_test;
import 'hooks_test.dart' as hooks_test;
import 'transport_test.dart' as transport_test;
import 'persistence_test.dart' as persistence_test;
import 'sync_store_test.dart' as sync_store_test;

void main() {
  // Run all test suites
  group('Schema Tests', schema_test.main);
  group('Clock Tests', clock_test.main);
  group('Operation Tests', operation_test.main);
  group('Record Tests', record_test.main);
  group('Hooks Tests', hooks_test.main);
  group('Transport Tests', transport_test.main);
  group('Persistence Tests', persistence_test.main);
  group('SyncStore Tests', sync_store_test.main);

  // Additional integration-style tests
  group('Integration', () {
    group('Schema and Operations', () {
      test('schema fields match operation payload types', () {
        final schema = Schema.v(1).collection('users', [
          Field.string('name', required: true),
          Field.int_('age'),
          Field.bool_('active'),
        ]).build();

        final op = CreateOp(
          opId: 'op_1',
          recordId: 'user_1',
          collection: 'users',
          payload: {
            'name': 'Alice',
            'age': 30,
            'active': true,
          },
          timestamp: 1000,
          clock: const LogicalClock(nodeId: 'device_1', counter: 1),
        );

        // Verify the payload matches schema field types
        expect(schema.hasCollection(op.collection), isTrue);
        final collectionSchema = schema[op.collection]!;
        expect(collectionSchema.fields.any((f) => f.name == 'name'), isTrue);
        expect(collectionSchema.fields.any((f) => f.name == 'age'), isTrue);
        expect(collectionSchema.fields.any((f) => f.name == 'active'), isTrue);
      });
    });

    group('Operations and Records', () {
      test('CreateOp payload can populate Record', () {
        final op = CreateOp(
          opId: 'op_create',
          recordId: 'item_1',
          collection: 'items',
          payload: {'name': 'Test Item', 'count': 5},
          timestamp: 1000,
          clock: const LogicalClock(nodeId: 'node_1', counter: 1),
        );

        // Simulate creating a Record from the operation
        final record = Record(
          id: op.recordId,
          collection: op.collection,
          version: 1,
          payload: op.payload,
          metadata: Metadata(
            createdAt: op.timestamp,
            updatedAt: op.timestamp,
            origin: Origin.local,
            clock: op.clock,
          ),
          deleted: false,
        );

        expect(record.id, equals(op.recordId));
        expect(record.collection, equals(op.collection));
        expect(record.payload, equals(op.payload));
        expect(record.metadata.clock, equals(op.clock));
      });

      test('UpdateOp payload replaces Record payload', () {
        final originalRecord = Record(
          id: 'item_1',
          collection: 'items',
          version: 1,
          payload: {'name': 'Original', 'count': 1},
          metadata: Metadata(
            createdAt: 1000,
            updatedAt: 1000,
            origin: Origin.local,
            clock: const LogicalClock(nodeId: 'n', counter: 1),
          ),
          deleted: false,
        );

        final updateOp = UpdateOp(
          opId: 'op_update',
          recordId: 'item_1',
          collection: 'items',
          payload: {'name': 'Updated', 'count': 10},
          baseVersion: 1,
          timestamp: 2000,
          clock: const LogicalClock(nodeId: 'n', counter: 2),
        );

        // Simulate applying the update
        final updatedRecord = Record(
          id: originalRecord.id,
          collection: originalRecord.collection,
          version: originalRecord.version + 1,
          payload: updateOp.payload,
          metadata: Metadata(
            createdAt: originalRecord.createdAt,
            updatedAt: updateOp.timestamp,
            origin: Origin.local,
            clock: updateOp.clock,
          ),
          deleted: false,
        );

        expect(updatedRecord.version, equals(2));
        expect(updatedRecord.payload['name'], equals('Updated'));
        expect(updatedRecord.payload['count'], equals(10));
      });

      test('DeleteOp marks Record as deleted', () {
        final record = Record(
          id: 'item_1',
          collection: 'items',
          version: 2,
          payload: {'name': 'To Delete'},
          metadata: Metadata(
            createdAt: 1000,
            updatedAt: 2000,
            origin: Origin.local,
            clock: const LogicalClock(nodeId: 'n', counter: 2),
          ),
          deleted: false,
        );

        final deleteOp = DeleteOp(
          opId: 'op_delete',
          recordId: 'item_1',
          collection: 'items',
          baseVersion: 2,
          timestamp: 3000,
          clock: const LogicalClock(nodeId: 'n', counter: 3),
        );

        // Simulate applying the delete
        final deletedRecord = Record(
          id: record.id,
          collection: record.collection,
          version: record.version + 1,
          payload: record.payload,
          metadata: Metadata(
            createdAt: record.createdAt,
            updatedAt: deleteOp.timestamp,
            origin: Origin.local,
            clock: deleteOp.clock,
          ),
          deleted: true,
        );

        expect(deletedRecord.deleted, isTrue);
        expect(deletedRecord.isActive, isFalse);
      });
    });

    group('Hooks and Operations', () {
      test('beforeInsert hook receives correct context', () {
        OperationContext? capturedContext;

        final hooks = StoreHooks(
          beforeInsert: (ctx) {
            capturedContext = ctx;
            return true;
          },
        );

        // Simulate what Collection.insert does
        const id = 'new_item';
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final item = {'name': 'Test'};

        final ctx = OperationContext<Map<String, dynamic>>(
          collection: 'items',
          recordId: id,
          item: item,
          timestamp: timestamp,
        );

        hooks.beforeInsert!(ctx);

        expect(capturedContext, isNotNull);
        expect(capturedContext!.collection, equals('items'));
        expect(capturedContext!.recordId, equals(id));
        expect(capturedContext!.item, equals(item));
      });

      test('beforeUpdate hook receives existing record', () {
        Record? capturedRecord;

        final hooks = StoreHooks(
          beforeUpdate: (ctx) {
            capturedRecord = ctx.existingRecord;
            return true;
          },
        );

        final existingRecord = Record(
          id: 'item_1',
          collection: 'items',
          version: 1,
          payload: {'name': 'Old'},
          metadata: Metadata(
            createdAt: 1000,
            updatedAt: 1000,
            origin: Origin.local,
            clock: const LogicalClock(nodeId: 'n', counter: 1),
          ),
          deleted: false,
        );

        final ctx = OperationContext<Map<String, dynamic>>(
          collection: 'items',
          recordId: 'item_1',
          item: {'name': 'New'},
          existingRecord: existingRecord,
          timestamp: 2000,
        );

        hooks.beforeUpdate!(ctx);

        expect(capturedRecord, isNotNull);
        expect(capturedRecord!.payload['name'], equals('Old'));
      });
    });

    group('Transport Results', () {
      test('PullResult operations can be parsed as Operation types', () {
        final pullResult = PullResult(
          operations: [
            CreateOp(
              opId: 'create_1',
              recordId: 'rec_1',
              collection: 'test',
              payload: {},
              timestamp: 1000,
              clock: const LogicalClock(nodeId: 's', counter: 1),
            ),
            UpdateOp(
              opId: 'update_1',
              recordId: 'rec_1',
              collection: 'test',
              payload: {'updated': true},
              baseVersion: 1,
              timestamp: 2000,
              clock: const LogicalClock(nodeId: 's', counter: 2),
            ),
            DeleteOp(
              opId: 'delete_1',
              recordId: 'rec_2',
              collection: 'test',
              baseVersion: 1,
              timestamp: 3000,
              clock: const LogicalClock(nodeId: 's', counter: 3),
            ),
          ],
          syncToken: 'token',
        );

        expect(pullResult.operations[0], isA<CreateOp>());
        expect(pullResult.operations[1], isA<UpdateOp>());
        expect(pullResult.operations[2], isA<DeleteOp>());
      });

      test('PushResult acknowledgedIds match operation opIds', () {
        final ops = [
          CreateOp(
            opId: 'local_op_1',
            recordId: 'rec_1',
            collection: 'test',
            payload: {},
            timestamp: 1000,
            clock: const LogicalClock(nodeId: 'l', counter: 1),
          ),
          CreateOp(
            opId: 'local_op_2',
            recordId: 'rec_2',
            collection: 'test',
            payload: {},
            timestamp: 2000,
            clock: const LogicalClock(nodeId: 'l', counter: 2),
          ),
        ];

        final pushResult = PushResult.ok(ops.map((op) => op.opId).toList());

        expect(pushResult.acknowledgedIds, contains('local_op_1'));
        expect(pushResult.acknowledgedIds, contains('local_op_2'));
      });
    });

    group('End-to-end serialization', () {
      test('Schema roundtrip through JSON', () {
        final original = Schema.v(1).collection('users', [
          Field.string('id', required: true),
          Field.string('name', required: true),
          Field.int_('age'),
          Field.bool_('verified'),
          Field.timestamp('createdAt'),
          Field.json('metadata'),
        ]).collection('posts', [
          Field.string('id', required: true),
          Field.string('userId', required: true),
          Field.string('title', required: true),
          Field.string('body'),
        ]).build();

        final json = original.toJson();
        final restored = Schema.fromJson(json);

        expect(restored.version, equals(original.version));
        expect(
          restored.collectionNames.toSet(),
          equals(original.collectionNames.toSet()),
        );

        for (final name in original.collectionNames) {
          expect(
            restored[name]!.fields.length,
            equals(original[name]!.fields.length),
          );
        }
      });

      test('Operation roundtrip through JSON', () {
        final operations = <Operation>[
          CreateOp(
            opId: 'create_op',
            recordId: 'rec_1',
            collection: 'test',
            payload: {
              'nested': {'key': 'value'},
              'array': [1, 2, 3],
            },
            timestamp: 1000,
            clock: const LogicalClock(nodeId: 'device', counter: 1),
          ),
          UpdateOp(
            opId: 'update_op',
            recordId: 'rec_1',
            collection: 'test',
            payload: {'updated': true},
            baseVersion: 1,
            timestamp: 2000,
            clock: const LogicalClock(nodeId: 'device', counter: 2),
          ),
          DeleteOp(
            opId: 'delete_op',
            recordId: 'rec_1',
            collection: 'test',
            baseVersion: 2,
            timestamp: 3000,
            clock: const LogicalClock(nodeId: 'device', counter: 3),
          ),
        ];

        for (final op in operations) {
          final json = op.toJson();
          final restored = Operation.fromJson(json);

          expect(restored.opId, equals(op.opId));
          expect(restored.recordId, equals(op.recordId));
          expect(restored.collection, equals(op.collection));
          expect(restored.timestamp, equals(op.timestamp));
          expect(restored.clock, equals(op.clock));
          expect(restored.runtimeType, equals(op.runtimeType));
        }
      });

      test('Record roundtrip through JSON', () {
        final original = Record(
          id: 'complex_record',
          collection: 'test_collection',
          version: 5,
          payload: {
            'string': 'text',
            'number': 42,
            'float': 3.14159,
            'bool': true,
            'null_value': null,
            'array': [1, 'two', 3.0],
            'nested': {
              'deep': {'value': 'found'},
            },
          },
          metadata: Metadata(
            createdAt: 1000,
            updatedAt: 5000,
            origin: Origin.remote,
            clock: const LogicalClock(nodeId: 'server', counter: 100),
          ),
          deleted: false,
        );

        final json = original.toJson();
        final restored = Record.fromJson(json);

        expect(restored.id, equals(original.id));
        expect(restored.collection, equals(original.collection));
        expect(restored.version, equals(original.version));
        expect(restored.payload, equals(original.payload));
        expect(restored.deleted, equals(original.deleted));
        expect(
          restored.metadata.createdAt,
          equals(original.metadata.createdAt),
        );
        expect(
          restored.metadata.updatedAt,
          equals(original.metadata.updatedAt),
        );
        expect(restored.metadata.origin, equals(original.metadata.origin));
        expect(restored.metadata.clock, equals(original.metadata.clock));
      });
    });
  });
}
