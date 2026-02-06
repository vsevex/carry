import 'package:flutter_test/flutter_test.dart';

import 'package:carry/carry.dart';

void main() {
  group('OperationContext', () {
    test('creates with required fields only', () {
      final ctx = OperationContext(
        collection: 'users',
        recordId: 'user_1',
        timestamp: 1000,
      );

      expect(ctx.collection, equals('users'));
      expect(ctx.recordId, equals('user_1'));
      expect(ctx.timestamp, equals(1000));
      expect(ctx.item, isNull);
      expect(ctx.existingRecord, isNull);
    });

    test('creates with item', () {
      final ctx = OperationContext<Map<String, dynamic>>(
        collection: 'posts',
        recordId: 'post_1',
        timestamp: 2000,
        item: {'title': 'Hello'},
      );

      expect(ctx.item, isNotNull);
      expect(ctx.item!['title'], equals('Hello'));
    });

    test('creates with existing record', () {
      final record = Record(
        id: 'existing_1',
        collection: 'test',
        version: 1,
        payload: {'old': 'data'},
        metadata: Metadata(
          createdAt: 1000,
          updatedAt: 1000,
          origin: Origin.local,
          clock: const LogicalClock(nodeId: 'n', counter: 1),
        ),
        deleted: false,
      );

      final ctx = OperationContext(
        collection: 'test',
        recordId: 'existing_1',
        timestamp: 3000,
        existingRecord: record,
      );

      expect(ctx.existingRecord, isNotNull);
      expect(ctx.existingRecord!.id, equals('existing_1'));
    });

    test('generic type works correctly', () {
      final ctx = OperationContext<String>(
        collection: 'strings',
        recordId: 'str_1',
        timestamp: 0,
        item: 'test string',
      );

      expect(ctx.item, isA<String>());
      expect(ctx.item, equals('test string'));
    });
  });

  group('SyncContext', () {
    test('creates with empty pending ops', () {
      final ctx = SyncContext(pendingOps: []);

      expect(ctx.pendingOps, isEmpty);
      expect(ctx.pulledOps, isNull);
      expect(ctx.conflicts, isNull);
    });

    test('creates with pending ops', () {
      final ops = [
        CreateOp(
          opId: 'op_1',
          recordId: 'rec_1',
          collection: 'test',
          payload: {},
          timestamp: 1000,
          clock: const LogicalClock(nodeId: 'n', counter: 1),
        ),
      ];

      final ctx = SyncContext(pendingOps: ops);

      expect(ctx.pendingOps.length, equals(1));
      expect(ctx.pendingOps[0].opId, equals('op_1'));
    });

    test('creates with pulled ops', () {
      final pulledOps = [
        UpdateOp(
          opId: 'remote_op',
          recordId: 'rec_1',
          collection: 'test',
          payload: {'updated': true},
          baseVersion: 1,
          timestamp: 2000,
          clock: const LogicalClock(nodeId: 'server', counter: 10),
        ),
      ];

      final ctx = SyncContext(
        pendingOps: [],
        pulledOps: pulledOps,
      );

      expect(ctx.pulledOps, isNotNull);
      expect(ctx.pulledOps!.length, equals(1));
    });

    test('creates with conflicts', () {
      final conflicts = [
        Conflict(
          recordId: 'conflict_rec',
          collection: 'test',
          localOpId: 'local_1',
          remoteOpId: 'remote_1',
          resolution: 'localWins',
          winnerId: 'local_1',
        ),
      ];

      final ctx = SyncContext(
        pendingOps: [],
        conflicts: conflicts,
      );

      expect(ctx.conflicts, isNotNull);
      expect(ctx.conflicts!.length, equals(1));
    });
  });

  group('StoreHooks', () {
    test('creates empty hooks with default constructor', () {
      const hooks = StoreHooks();

      expect(hooks.beforeInsert, isNull);
      expect(hooks.afterInsert, isNull);
      expect(hooks.beforeUpdate, isNull);
      expect(hooks.afterUpdate, isNull);
      expect(hooks.beforeDelete, isNull);
      expect(hooks.afterDelete, isNull);
      expect(hooks.beforeSync, isNull);
      expect(hooks.afterSync, isNull);
      expect(hooks.onSyncError, isNull);
      expect(hooks.onConflict, isNull);
    });

    test('StoreHooks.none is empty', () {
      expect(StoreHooks.none.beforeInsert, isNull);
      expect(StoreHooks.none.afterInsert, isNull);
      expect(StoreHooks.none.beforeUpdate, isNull);
      expect(StoreHooks.none.afterUpdate, isNull);
      expect(StoreHooks.none.beforeDelete, isNull);
      expect(StoreHooks.none.afterDelete, isNull);
      expect(StoreHooks.none.beforeSync, isNull);
      expect(StoreHooks.none.afterSync, isNull);
      expect(StoreHooks.none.onSyncError, isNull);
      expect(StoreHooks.none.onConflict, isNull);
    });

    test('creates hooks with beforeInsert callback', () {
      var callCount = 0;
      final hooks = StoreHooks(
        beforeInsert: (ctx) {
          callCount++;
          return true;
        },
      );

      final ctx = OperationContext(
        collection: 'test',
        recordId: '1',
        timestamp: 0,
      );

      expect(hooks.beforeInsert, isNotNull);
      expect(hooks.beforeInsert!(ctx), isTrue);
      expect(callCount, equals(1));
    });

    test('beforeInsert can cancel operation by returning false', () {
      final hooks = StoreHooks(
        beforeInsert: (ctx) => false,
      );

      final ctx = OperationContext(
        collection: 'test',
        recordId: '1',
        timestamp: 0,
      );

      expect(hooks.beforeInsert!(ctx), isFalse);
    });

    test('creates hooks with afterInsert callback', () {
      Record? capturedRecord;
      final hooks = StoreHooks(
        afterInsert: (ctx, record) {
          capturedRecord = record;
        },
      );

      final ctx = OperationContext(
        collection: 'test',
        recordId: '1',
        timestamp: 0,
      );

      final record = Record(
        id: '1',
        collection: 'test',
        version: 1,
        payload: {},
        metadata: Metadata(
          createdAt: 0,
          updatedAt: 0,
          origin: Origin.local,
          clock: const LogicalClock(nodeId: 'n', counter: 1),
        ),
        deleted: false,
      );

      hooks.afterInsert!(ctx, record);

      expect(capturedRecord, isNotNull);
      expect(capturedRecord!.id, equals('1'));
    });

    test('creates hooks with all operation callbacks', () {
      final hooks = StoreHooks(
        beforeInsert: (ctx) => true,
        afterInsert: (ctx, record) {},
        beforeUpdate: (ctx) => true,
        afterUpdate: (ctx, record) {},
        beforeDelete: (ctx) => true,
        afterDelete: (ctx) {},
      );

      expect(hooks.beforeInsert, isNotNull);
      expect(hooks.afterInsert, isNotNull);
      expect(hooks.beforeUpdate, isNotNull);
      expect(hooks.afterUpdate, isNotNull);
      expect(hooks.beforeDelete, isNotNull);
      expect(hooks.afterDelete, isNotNull);
    });

    test('creates hooks with sync callbacks', () {
      final hooks = StoreHooks(
        beforeSync: (ctx) => true,
        afterSync: (ctx) {},
        onSyncError: (error, ctx) {},
        onConflict: (conflict) {},
      );

      expect(hooks.beforeSync, isNotNull);
      expect(hooks.afterSync, isNotNull);
      expect(hooks.onSyncError, isNotNull);
      expect(hooks.onConflict, isNotNull);
    });

    test('beforeSync can cancel sync by returning false', () {
      final hooks = StoreHooks(
        beforeSync: (ctx) => false,
      );

      final ctx = SyncContext(pendingOps: []);

      expect(hooks.beforeSync!(ctx), isFalse);
    });

    test('onSyncError receives error and context', () {
      Object? capturedError;
      SyncContext? capturedContext;

      final hooks = StoreHooks(
        onSyncError: (error, ctx) {
          capturedError = error;
          capturedContext = ctx;
        },
      );

      final ctx = SyncContext(pendingOps: []);
      final error = Exception('Test error');

      hooks.onSyncError!(error, ctx);

      expect(capturedError, equals(error));
      expect(capturedContext, equals(ctx));
    });

    test('onConflict receives conflict', () {
      Conflict? capturedConflict;

      final hooks = StoreHooks(
        onConflict: (conflict) {
          capturedConflict = conflict;
        },
      );

      final conflict = Conflict(
        recordId: 'rec',
        collection: 'col',
        localOpId: 'local',
        remoteOpId: 'remote',
        resolution: 'localWins',
        winnerId: 'local',
      );

      hooks.onConflict!(conflict);

      expect(capturedConflict, isNotNull);
      expect(capturedConflict!.recordId, equals('rec'));
    });

    group('merge', () {
      test('other hooks take precedence', () {
        final hooks1 = StoreHooks(
          beforeInsert: (ctx) => true,
        );

        final hooks2 = StoreHooks(
          beforeInsert: (ctx) => false,
        );

        final merged = hooks1.merge(hooks2);
        final ctx = OperationContext(
          collection: 'test',
          recordId: '1',
          timestamp: 0,
        );

        expect(merged.beforeInsert!(ctx), isFalse);
      });

      test('preserves hooks from first when not overridden', () {
        final hooks1 = StoreHooks(
          beforeInsert: (ctx) => true,
          beforeUpdate: (ctx) => true,
        );

        final hooks2 = StoreHooks(
          beforeInsert: (ctx) => false,
        );

        final merged = hooks1.merge(hooks2);

        expect(merged.beforeUpdate, isNotNull);
      });

      test('adds hooks from second that are not in first', () {
        final hooks1 = StoreHooks(
          beforeInsert: (ctx) => true,
        );

        final hooks2 = StoreHooks(
          afterInsert: (ctx, record) {},
        );

        final merged = hooks1.merge(hooks2);

        expect(merged.beforeInsert, isNotNull);
        expect(merged.afterInsert, isNotNull);
      });

      test('merges all hook types', () {
        final hooks1 = StoreHooks(
          beforeInsert: (ctx) => true,
          beforeUpdate: (ctx) => true,
          beforeDelete: (ctx) => true,
          beforeSync: (ctx) => true,
          onSyncError: (e, ctx) {},
        );

        final hooks2 = StoreHooks(
          afterInsert: (ctx, record) {},
          afterUpdate: (ctx, record) {},
          afterDelete: (ctx) {},
          afterSync: (ctx) {},
          onConflict: (conflict) {},
        );

        final merged = hooks1.merge(hooks2);

        expect(merged.beforeInsert, isNotNull);
        expect(merged.afterInsert, isNotNull);
        expect(merged.beforeUpdate, isNotNull);
        expect(merged.afterUpdate, isNotNull);
        expect(merged.beforeDelete, isNotNull);
        expect(merged.afterDelete, isNotNull);
        expect(merged.beforeSync, isNotNull);
        expect(merged.afterSync, isNotNull);
        expect(merged.onSyncError, isNotNull);
        expect(merged.onConflict, isNotNull);
      });

      test('merge with empty hooks returns original', () {
        var called = false;
        final hooks = StoreHooks(
          beforeInsert: (ctx) {
            called = true;
            return true;
          },
        );

        final merged = hooks.merge(const StoreHooks());
        final ctx = OperationContext(
          collection: 'test',
          recordId: '1',
          timestamp: 0,
        );

        merged.beforeInsert!(ctx);
        expect(called, isTrue);
      });

      test('empty hooks merge with other returns other', () {
        final hooks = StoreHooks(
          beforeInsert: (ctx) => false,
        );

        final merged = const StoreHooks().merge(hooks);
        final ctx = OperationContext(
          collection: 'test',
          recordId: '1',
          timestamp: 0,
        );

        expect(merged.beforeInsert!(ctx), isFalse);
      });
    });
  });

  group('OperationCancelledException', () {
    test('creates with operation, collection, and recordId', () {
      final ex = OperationCancelledException(
        operation: 'insert',
        collection: 'users',
        recordId: 'user_1',
      );

      expect(ex.operation, equals('insert'));
      expect(ex.collection, equals('users'));
      expect(ex.recordId, equals('user_1'));
    });

    test('toString contains all fields', () {
      final ex = OperationCancelledException(
        operation: 'update',
        collection: 'posts',
        recordId: 'post_123',
      );

      final str = ex.toString();

      expect(str, contains('update'));
      expect(str, contains('posts'));
      expect(str, contains('post_123'));
      expect(str, contains('cancelled by hook'));
    });

    test('works for all operation types', () {
      final insert = OperationCancelledException(
        operation: 'insert',
        collection: 'test',
        recordId: '1',
      );
      expect(insert.toString(), contains('insert'));

      final update = OperationCancelledException(
        operation: 'update',
        collection: 'test',
        recordId: '1',
      );
      expect(update.toString(), contains('update'));

      final delete = OperationCancelledException(
        operation: 'delete',
        collection: 'test',
        recordId: '1',
      );
      expect(delete.toString(), contains('delete'));
    });

    test('is an Exception', () {
      final ex = OperationCancelledException(
        operation: 'insert',
        collection: 'test',
        recordId: '1',
      );

      expect(ex, isA<Exception>());
    });
  });
}
