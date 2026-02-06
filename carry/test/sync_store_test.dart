import 'package:flutter_test/flutter_test.dart';

import 'package:carry/carry.dart';

void main() {
  group('SyncResult', () {
    test('creates with all fields', () {
      final result = SyncResult(
        pushedCount: 5,
        pulledCount: 10,
        conflicts: [],
        success: true,
      );

      expect(result.pushedCount, equals(5));
      expect(result.pulledCount, equals(10));
      expect(result.conflicts, isEmpty);
      expect(result.success, isTrue);
      expect(result.error, isNull);
    });

    test('creates with error', () {
      final result = SyncResult(
        pushedCount: 0,
        pulledCount: 0,
        conflicts: [],
        success: false,
        error: 'Connection failed',
      );

      expect(result.success, isFalse);
      expect(result.error, equals('Connection failed'));
    });

    test('failed factory creates error result', () {
      final result = SyncResult.failed('No transport configured');

      expect(result.success, isFalse);
      expect(result.pushedCount, equals(0));
      expect(result.pulledCount, equals(0));
      expect(result.conflicts, isEmpty);
      expect(result.error, equals('No transport configured'));
    });

    test('creates with conflicts', () {
      final conflicts = [
        Conflict(
          recordId: 'rec_1',
          collection: 'items',
          localOpId: 'local_1',
          remoteOpId: 'remote_1',
          resolution: 'localWins',
          winnerId: 'local_1',
        ),
        Conflict(
          recordId: 'rec_2',
          collection: 'items',
          localOpId: 'local_2',
          remoteOpId: 'remote_2',
          resolution: 'remoteWins',
          winnerId: 'remote_2',
        ),
      ];

      final result = SyncResult(
        pushedCount: 3,
        pulledCount: 2,
        conflicts: conflicts,
        success: true,
      );

      expect(result.conflicts.length, equals(2));
      expect(result.conflicts[0].resolution, equals('localWins'));
      expect(result.conflicts[1].resolution, equals('remoteWins'));
    });
  });

  group('MergeStrategy', () {
    test('clockWins has value 0', () {
      expect(MergeStrategy.clockWins.value, equals(0));
    });

    test('timestampWins has value 1', () {
      expect(MergeStrategy.timestampWins.value, equals(1));
    });

    test('all strategies have unique values', () {
      final values = MergeStrategy.values.map((s) => s.value).toSet();
      expect(values.length, equals(MergeStrategy.values.length));
    });
  });

  group('NativeStoreException', () {
    test('creates with message', () {
      final ex = NativeStoreException('Test error message');

      expect(ex.message, equals('Test error message'));
    });

    test('toString formats correctly', () {
      final ex = NativeStoreException('Operation failed');

      expect(
        ex.toString(),
        equals('NativeStoreException: Operation failed'),
      );
    });

    test('is an Exception', () {
      final ex = NativeStoreException('error');

      expect(ex, isA<Exception>());
    });
  });

  // Note: SyncStore functionality that requires the native library
  // should be tested in integration tests that have access to the
  // compiled native library (libcarry_engine).
  //
  // The following tests would require integration test setup:
  // - SyncStore.init()
  // - SyncStore.collection()
  // - SyncStore.pendingCount
  // - SyncStore.pendingOps
  // - SyncStore.exportSnapshot()
  // - SyncStore.clock
  // - SyncStore.sync()
  // - SyncStore.save()
  // - SyncStore.close()
  //
  // See engine/tests/ for native library tests.
}
