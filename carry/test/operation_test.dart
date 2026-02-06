import 'package:flutter_test/flutter_test.dart';

import 'package:carry/carry.dart';

void main() {
  group('CreateOp', () {
    test('creates with all required fields', () {
      final op = CreateOp(
        opId: 'op_create_1',
        recordId: 'record_1',
        collection: 'users',
        payload: {'name': 'Alice', 'email': 'alice@example.com'},
        timestamp: 1000,
        clock: const LogicalClock(nodeId: 'device_1', counter: 1),
      );

      expect(op.opId, equals('op_create_1'));
      expect(op.recordId, equals('record_1'));
      expect(op.collection, equals('users'));
      expect(op.payload['name'], equals('Alice'));
      expect(op.timestamp, equals(1000));
      expect(op.clock.nodeId, equals('device_1'));
    });

    test('toJson serializes correctly', () {
      final op = CreateOp(
        opId: 'op_1',
        recordId: 'rec_1',
        collection: 'posts',
        payload: {'title': 'Hello'},
        timestamp: 2000,
        clock: const LogicalClock(nodeId: 'n1', counter: 5),
      );

      final json = op.toJson();

      expect(json['type'], equals('create'));
      expect(json['opId'], equals('op_1'));
      expect(json['id'], equals('rec_1'));
      expect(json['collection'], equals('posts'));
      expect(json['payload'], equals({'title': 'Hello'}));
      expect(json['timestamp'], equals(2000));
      expect(json['clock']['nodeId'], equals('n1'));
      expect(json['clock']['counter'], equals(5));
    });

    test('fromJson parses correctly', () {
      final json = {
        'type': 'create',
        'opId': 'parsed_op',
        'id': 'parsed_rec',
        'collection': 'items',
        'payload': {'key': 'value'},
        'timestamp': 3000,
        'clock': {'nodeId': 'node_x', 'counter': 10},
      };

      final op = CreateOp.fromJson(json);

      expect(op.opId, equals('parsed_op'));
      expect(op.recordId, equals('parsed_rec'));
      expect(op.collection, equals('items'));
      expect(op.payload['key'], equals('value'));
      expect(op.timestamp, equals(3000));
      expect(op.clock.nodeId, equals('node_x'));
    });

    test('round-trip serialization preserves data', () {
      final original = CreateOp(
        opId: 'op_roundtrip',
        recordId: 'rec_roundtrip',
        collection: 'test',
        payload: {
          'nested': {
            'data': [1, 2, 3],
          },
        },
        timestamp: 5000,
        clock: const LogicalClock(nodeId: 'rt_node', counter: 99),
      );

      final json = original.toJson();
      final restored = CreateOp.fromJson(json);

      expect(restored.opId, equals(original.opId));
      expect(restored.recordId, equals(original.recordId));
      expect(restored.collection, equals(original.collection));
      expect(restored.payload, equals(original.payload));
      expect(restored.timestamp, equals(original.timestamp));
      expect(restored.clock, equals(original.clock));
    });

    test('handles empty payload', () {
      final op = CreateOp(
        opId: 'op_empty',
        recordId: 'rec_empty',
        collection: 'empty',
        payload: {},
        timestamp: 0,
        clock: const LogicalClock(nodeId: 'n', counter: 0),
      );

      final json = op.toJson();
      expect(json['payload'], isEmpty);
    });
  });

  group('UpdateOp', () {
    test('creates with all required fields including baseVersion', () {
      final op = UpdateOp(
        opId: 'op_update_1',
        recordId: 'record_1',
        collection: 'users',
        payload: {'name': 'Bob'},
        baseVersion: 1,
        timestamp: 2000,
        clock: const LogicalClock(nodeId: 'device_1', counter: 2),
      );

      expect(op.opId, equals('op_update_1'));
      expect(op.recordId, equals('record_1'));
      expect(op.baseVersion, equals(1));
    });

    test('toJson serializes correctly with baseVersion', () {
      final op = UpdateOp(
        opId: 'op_2',
        recordId: 'rec_2',
        collection: 'posts',
        payload: {'title': 'Updated'},
        baseVersion: 5,
        timestamp: 3000,
        clock: const LogicalClock(nodeId: 'n2', counter: 10),
      );

      final json = op.toJson();

      expect(json['type'], equals('update'));
      expect(json['opId'], equals('op_2'));
      expect(json['id'], equals('rec_2'));
      expect(json['baseVersion'], equals(5));
    });

    test('fromJson parses correctly', () {
      final json = {
        'type': 'update',
        'opId': 'update_op',
        'id': 'update_rec',
        'collection': 'items',
        'payload': {'updated': true},
        'baseVersion': 3,
        'timestamp': 4000,
        'clock': {'nodeId': 'update_node', 'counter': 15},
      };

      final op = UpdateOp.fromJson(json);

      expect(op.opId, equals('update_op'));
      expect(op.baseVersion, equals(3));
      expect(op.payload['updated'], isTrue);
    });

    test('round-trip serialization preserves baseVersion', () {
      final original = UpdateOp(
        opId: 'op_rt',
        recordId: 'rec_rt',
        collection: 'test',
        payload: {'data': 'test'},
        baseVersion: 42,
        timestamp: 6000,
        clock: const LogicalClock(nodeId: 'rt', counter: 50),
      );

      final json = original.toJson();
      final restored = UpdateOp.fromJson(json);

      expect(restored.baseVersion, equals(original.baseVersion));
    });
  });

  group('DeleteOp', () {
    test('creates with all required fields', () {
      final op = DeleteOp(
        opId: 'op_delete_1',
        recordId: 'record_1',
        collection: 'users',
        baseVersion: 2,
        timestamp: 3000,
        clock: const LogicalClock(nodeId: 'device_1', counter: 3),
      );

      expect(op.opId, equals('op_delete_1'));
      expect(op.recordId, equals('record_1'));
      expect(op.baseVersion, equals(2));
    });

    test('toJson serializes correctly', () {
      final op = DeleteOp(
        opId: 'op_3',
        recordId: 'rec_3',
        collection: 'posts',
        baseVersion: 7,
        timestamp: 4000,
        clock: const LogicalClock(nodeId: 'n3', counter: 20),
      );

      final json = op.toJson();

      expect(json['type'], equals('delete'));
      expect(json['opId'], equals('op_3'));
      expect(json['id'], equals('rec_3'));
      expect(json['baseVersion'], equals(7));
      expect(json.containsKey('payload'), isFalse);
    });

    test('fromJson parses correctly', () {
      final json = {
        'type': 'delete',
        'opId': 'delete_op',
        'id': 'delete_rec',
        'collection': 'items',
        'baseVersion': 8,
        'timestamp': 5000,
        'clock': {'nodeId': 'delete_node', 'counter': 25},
      };

      final op = DeleteOp.fromJson(json);

      expect(op.opId, equals('delete_op'));
      expect(op.baseVersion, equals(8));
    });

    test('payload property returns empty map', () {
      final op = DeleteOp(
        opId: 'op_del',
        recordId: 'rec_del',
        collection: 'test',
        baseVersion: 1,
        timestamp: 0,
        clock: const LogicalClock(nodeId: 'n', counter: 0),
      );

      expect(op.payload, isEmpty);
      expect(op.payload, isA<Map<String, dynamic>>());
    });
  });

  group('Operation.fromJson', () {
    test('parses CreateOp correctly', () {
      final json = {
        'type': 'create',
        'opId': 'op_1',
        'id': 'rec_1',
        'collection': 'test',
        'payload': {'data': 'value'},
        'timestamp': 1000,
        'clock': {'nodeId': 'n', 'counter': 1},
      };

      final op = Operation.fromJson(json);

      expect(op, isA<CreateOp>());
      expect(op.opId, equals('op_1'));
    });

    test('parses UpdateOp correctly', () {
      final json = {
        'type': 'update',
        'opId': 'op_2',
        'id': 'rec_2',
        'collection': 'test',
        'payload': {'data': 'updated'},
        'baseVersion': 1,
        'timestamp': 2000,
        'clock': {'nodeId': 'n', 'counter': 2},
      };

      final op = Operation.fromJson(json);

      expect(op, isA<UpdateOp>());
      expect((op as UpdateOp).baseVersion, equals(1));
    });

    test('parses DeleteOp correctly', () {
      final json = {
        'type': 'delete',
        'opId': 'op_3',
        'id': 'rec_3',
        'collection': 'test',
        'baseVersion': 2,
        'timestamp': 3000,
        'clock': {'nodeId': 'n', 'counter': 3},
      };

      final op = Operation.fromJson(json);

      expect(op, isA<DeleteOp>());
      expect((op as DeleteOp).baseVersion, equals(2));
    });

    test('throws ArgumentError for unknown type', () {
      final json = {
        'type': 'unknown',
        'opId': 'op',
        'id': 'rec',
        'collection': 'test',
        'timestamp': 0,
        'clock': {'nodeId': 'n', 'counter': 0},
      };

      expect(() => Operation.fromJson(json), throwsArgumentError);
    });

    test('throws ArgumentError for null type', () {
      final json = {
        'opId': 'op',
        'id': 'rec',
        'collection': 'test',
        'timestamp': 0,
        'clock': {'nodeId': 'n', 'counter': 0},
      };

      expect(() => Operation.fromJson(json), throwsArgumentError);
    });
  });

  group('ApplyResult', () {
    test('creates with all fields', () {
      final result = ApplyResult(
        opId: 'applied_op',
        recordId: 'applied_rec',
        version: 5,
      );

      expect(result.opId, equals('applied_op'));
      expect(result.recordId, equals('applied_rec'));
      expect(result.version, equals(5));
    });

    test('fromJson parses correctly', () {
      final json = {
        'opId': 'parsed_op',
        'recordId': 'parsed_rec',
        'version': 10,
      };

      final result = ApplyResult.fromJson(json);

      expect(result.opId, equals('parsed_op'));
      expect(result.recordId, equals('parsed_rec'));
      expect(result.version, equals(10));
    });
  });

  group('ReconcileResult', () {
    test('creates with all lists', () {
      final result = ReconcileResult(
        acceptedLocal: ['op1', 'op2'],
        rejectedLocal: ['op3'],
        acceptedRemote: ['op4', 'op5'],
        rejectedRemote: [],
        conflicts: [],
      );

      expect(result.acceptedLocal, equals(['op1', 'op2']));
      expect(result.rejectedLocal, equals(['op3']));
      expect(result.acceptedRemote, equals(['op4', 'op5']));
      expect(result.rejectedRemote, isEmpty);
      expect(result.conflicts, isEmpty);
    });

    test('fromJson parses correctly', () {
      final json = {
        'acceptedLocal': ['a1', 'a2'],
        'rejectedLocal': ['r1'],
        'appliedRemote': ['ar1', 'ar2', 'ar3'],
        'rejectedRemote': ['rr1'],
        'conflicts': [],
      };

      final result = ReconcileResult.fromJson(json);

      expect(result.acceptedLocal, equals(['a1', 'a2']));
      expect(result.rejectedLocal, equals(['r1']));
      expect(result.acceptedRemote, equals(['ar1', 'ar2', 'ar3']));
      expect(result.rejectedRemote, equals(['rr1']));
    });

    test('fromJson parses conflicts', () {
      final json = {
        'acceptedLocal': [],
        'rejectedLocal': [],
        'appliedRemote': [],
        'rejectedRemote': [],
        'conflicts': [
          {
            'recordId': 'rec_conflict',
            'collection': 'test',
            'localOpId': 'local_op',
            'remoteOpId': 'remote_op',
            'resolution': {'localWins': 'local_op'},
          },
        ],
      };

      final result = ReconcileResult.fromJson(json);

      expect(result.conflicts.length, equals(1));
      expect(result.conflicts[0].recordId, equals('rec_conflict'));
    });
  });

  group('Conflict', () {
    test('creates with all fields', () {
      final conflict = Conflict(
        recordId: 'conflict_rec',
        collection: 'items',
        localOpId: 'local_123',
        remoteOpId: 'remote_456',
        resolution: 'localWins',
        winnerId: 'local_123',
      );

      expect(conflict.recordId, equals('conflict_rec'));
      expect(conflict.collection, equals('items'));
      expect(conflict.localOpId, equals('local_123'));
      expect(conflict.remoteOpId, equals('remote_456'));
      expect(conflict.resolution, equals('localWins'));
      expect(conflict.winnerId, equals('local_123'));
    });

    test('fromJson parses localWins resolution', () {
      final json = {
        'recordId': 'rec_1',
        'collection': 'col_1',
        'localOpId': 'local_1',
        'remoteOpId': 'remote_1',
        'resolution': {'localWins': 'local_1'},
      };

      final conflict = Conflict.fromJson(json);

      expect(conflict.resolution, equals('localWins'));
      expect(conflict.winnerId, equals('local_1'));
    });

    test('fromJson parses remoteWins resolution', () {
      final json = {
        'recordId': 'rec_2',
        'collection': 'col_2',
        'localOpId': 'local_2',
        'remoteOpId': 'remote_2',
        'resolution': {'remoteWins': 'remote_2'},
      };

      final conflict = Conflict.fromJson(json);

      expect(conflict.resolution, equals('remoteWins'));
      expect(conflict.winnerId, equals('remote_2'));
    });
  });
}
