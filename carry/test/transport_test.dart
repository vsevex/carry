import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:carry/carry.dart';

void main() {
  group('PullResult', () {
    test('creates with operations and token', () {
      final result = PullResult(
        operations: [],
        syncToken: 'token_123',
      );

      expect(result.operations, isEmpty);
      expect(result.syncToken, equals('token_123'));
      expect(result.hasMore, isFalse);
    });

    test('creates with hasMore flag', () {
      final result = PullResult(
        operations: [],
        syncToken: 'token',
        hasMore: true,
      );

      expect(result.hasMore, isTrue);
    });

    test('creates with operations', () {
      final ops = [
        CreateOp(
          opId: 'op_1',
          recordId: 'rec_1',
          collection: 'test',
          payload: {'key': 'value'},
          timestamp: 1000,
          clock: const LogicalClock(nodeId: 'server', counter: 1),
        ),
      ];

      final result = PullResult(operations: ops);

      expect(result.operations.length, equals(1));
      expect(result.operations[0].opId, equals('op_1'));
    });

    test('syncToken can be null', () {
      final result = PullResult(operations: []);

      expect(result.syncToken, isNull);
    });
  });

  group('PushResult', () {
    test('ok factory creates success result', () {
      final result = PushResult.ok(['op_1', 'op_2', 'op_3']);

      expect(result.success, isTrue);
      expect(result.acknowledgedIds, equals(['op_1', 'op_2', 'op_3']));
      expect(result.error, isNull);
    });

    test('ok factory with empty list', () {
      final result = PushResult.ok([]);

      expect(result.success, isTrue);
      expect(result.acknowledgedIds, isEmpty);
    });

    test('failed factory creates failed result', () {
      final result = PushResult.failed('Connection timeout');

      expect(result.success, isFalse);
      expect(result.acknowledgedIds, isEmpty);
      expect(result.error, equals('Connection timeout'));
    });

    test('creates with all parameters', () {
      final result = PushResult(
        success: true,
        acknowledgedIds: ['a', 'b'],
      );

      expect(result.success, isTrue);
      expect(result.acknowledgedIds, equals(['a', 'b']));
    });

    test('error can be set on failed result', () {
      final result = PushResult(
        success: false,
        acknowledgedIds: [],
        error: 'Server error 500',
      );

      expect(result.error, equals('Server error 500'));
    });
  });

  group('HttpTransportException', () {
    test('creates with message only', () {
      final ex = HttpTransportException('Network error');

      expect(ex.message, equals('Network error'));
      expect(ex.statusCode, isNull);
    });

    test('creates with message and status code', () {
      final ex = HttpTransportException('Not found', statusCode: 404);

      expect(ex.message, equals('Not found'));
      expect(ex.statusCode, equals(404));
    });

    test('toString without status code', () {
      final ex = HttpTransportException('Connection failed');

      expect(
        ex.toString(),
        equals('HttpTransportException: Connection failed'),
      );
    });

    test('toString with status code', () {
      final ex = HttpTransportException('Unauthorized', statusCode: 401);

      expect(
        ex.toString(),
        equals('HttpTransportException: 401 - Unauthorized'),
      );
    });
  });

  group('HttpTransport', () {
    late MockClient mockClient;

    test('creates with required parameters', () {
      final transport = HttpTransport(
        baseUrl: 'https://api.example.com',
        nodeId: 'device_1',
      );

      expect(transport.baseUrl, equals('https://api.example.com'));
      expect(transport.nodeId, equals('device_1'));
      expect(transport.syncPath, equals('/sync'));
      expect(transport.timeout, equals(const Duration(seconds: 30)));
      expect(transport.pullLimit, equals(100));
    });

    test('creates with custom parameters', () {
      final transport = HttpTransport(
        baseUrl: 'https://custom.api.com',
        nodeId: 'node_xyz',
        syncPath: '/api/v1/sync',
        timeout: const Duration(seconds: 60),
        pullLimit: 50,
        headers: {'Authorization': 'Bearer token123'},
      );

      expect(transport.syncPath, equals('/api/v1/sync'));
      expect(transport.timeout, equals(const Duration(seconds: 60)));
      expect(transport.pullLimit, equals(50));
      expect(transport.headers?['Authorization'], equals('Bearer token123'));
    });

    group('pull', () {
      test('returns operations from server', () async {
        mockClient = MockClient((request) async {
          expect(request.method, equals('GET'));
          expect(request.url.path, equals('/sync'));
          expect(request.url.queryParameters['limit'], equals('100'));

          return http.Response(
            jsonEncode({
              'operations': [
                {
                  'type': 'create',
                  'opId': 'server_op_1',
                  'id': 'rec_1',
                  'collection': 'items',
                  'payload': {'name': 'Test'},
                  'timestamp': 1000,
                  'clock': {'nodeId': 'server', 'counter': 1},
                },
              ],
              'syncToken': 'new_token_abc',
              'hasMore': false,
            }),
            200,
          );
        });

        final transport = HttpTransport(
          baseUrl: 'https://api.test.com',
          nodeId: 'test_node',
          client: mockClient,
        );

        final result = await transport.pull(null);

        expect(result.operations.length, equals(1));
        expect(result.operations[0], isA<CreateOp>());
        expect(result.syncToken, equals('new_token_abc'));
        expect(result.hasMore, isFalse);
      });

      test('includes since parameter when token provided', () async {
        mockClient = MockClient((request) async {
          expect(request.url.queryParameters['since'], equals('prev_token'));

          return http.Response(
            jsonEncode({
              'operations': [],
              'syncToken': 'next_token',
            }),
            200,
          );
        });

        final transport = HttpTransport(
          baseUrl: 'https://api.test.com',
          nodeId: 'test_node',
          client: mockClient,
        );

        await transport.pull('prev_token');
      });

      test('throws on non-200 response', () async {
        mockClient = MockClient((request) async {
          return http.Response('Internal Server Error', 500);
        });

        final transport = HttpTransport(
          baseUrl: 'https://api.test.com',
          nodeId: 'test_node',
          client: mockClient,
        );

        expect(
          () => transport.pull(null),
          throwsA(isA<HttpTransportException>()),
        );
      });

      test('handles empty operations list', () async {
        mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'operations': [],
              'syncToken': 'empty_token',
            }),
            200,
          );
        });

        final transport = HttpTransport(
          baseUrl: 'https://api.test.com',
          nodeId: 'test_node',
          client: mockClient,
        );

        final result = await transport.pull(null);

        expect(result.operations, isEmpty);
      });

      test('handles missing syncToken', () async {
        mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({'operations': []}),
            200,
          );
        });

        final transport = HttpTransport(
          baseUrl: 'https://api.test.com',
          nodeId: 'test_node',
          client: mockClient,
        );

        final result = await transport.pull(null);

        expect(result.syncToken, isNull);
      });

      test('includes custom headers', () async {
        mockClient = MockClient((request) async {
          expect(request.headers['Authorization'], equals('Bearer secret'));
          expect(request.headers['X-Custom'], equals('custom_value'));

          return http.Response(
            jsonEncode({'operations': []}),
            200,
          );
        });

        final transport = HttpTransport(
          baseUrl: 'https://api.test.com',
          nodeId: 'test_node',
          client: mockClient,
          headers: {
            'Authorization': 'Bearer secret',
            'X-Custom': 'custom_value',
          },
        );

        await transport.pull(null);
      });

      test('sets Content-Type and Accept headers', () async {
        mockClient = MockClient((request) async {
          expect(request.headers['Content-Type'], equals('application/json'));
          expect(request.headers['Accept'], equals('application/json'));

          return http.Response(
            jsonEncode({'operations': []}),
            200,
          );
        });

        final transport = HttpTransport(
          baseUrl: 'https://api.test.com',
          nodeId: 'test_node',
          client: mockClient,
        );

        await transport.pull(null);
      });
    });

    group('push', () {
      test('returns empty list for empty operations', () async {
        mockClient = MockClient((request) async {
          fail('Should not make request for empty operations');
        });

        final transport = HttpTransport(
          baseUrl: 'https://api.test.com',
          nodeId: 'test_node',
          client: mockClient,
        );

        final result = await transport.push([]);

        expect(result.success, isTrue);
        expect(result.acknowledgedIds, isEmpty);
      });

      test('sends operations to server', () async {
        mockClient = MockClient((request) async {
          expect(request.method, equals('POST'));
          expect(request.url.path, equals('/sync'));

          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['nodeId'], equals('test_node'));
          expect(body['operations'], isA<List>());
          expect((body['operations'] as List).length, equals(2));

          return http.Response(
            jsonEncode({
              'accepted': ['op_1', 'op_2'],
            }),
            200,
          );
        });

        final transport = HttpTransport(
          baseUrl: 'https://api.test.com',
          nodeId: 'test_node',
          client: mockClient,
        );

        final ops = [
          CreateOp(
            opId: 'op_1',
            recordId: 'rec_1',
            collection: 'test',
            payload: {'data': 1},
            timestamp: 1000,
            clock: const LogicalClock(nodeId: 'test_node', counter: 1),
          ),
          UpdateOp(
            opId: 'op_2',
            recordId: 'rec_1',
            collection: 'test',
            payload: {'data': 2},
            baseVersion: 1,
            timestamp: 2000,
            clock: const LogicalClock(nodeId: 'test_node', counter: 2),
          ),
        ];

        final result = await transport.push(ops);

        expect(result.success, isTrue);
        expect(result.acknowledgedIds, equals(['op_1', 'op_2']));
      });

      test('handles server returning subset of acknowledged', () async {
        mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'accepted': ['op_1'],
              'rejected': [
                {'opId': 'op_2', 'reason': 'conflict'},
              ],
            }),
            200,
          );
        });

        final transport = HttpTransport(
          baseUrl: 'https://api.test.com',
          nodeId: 'test_node',
          client: mockClient,
        );

        final ops = [
          CreateOp(
            opId: 'op_1',
            recordId: 'rec_1',
            collection: 'test',
            payload: {},
            timestamp: 1000,
            clock: const LogicalClock(nodeId: 'n', counter: 1),
          ),
          CreateOp(
            opId: 'op_2',
            recordId: 'rec_2',
            collection: 'test',
            payload: {},
            timestamp: 2000,
            clock: const LogicalClock(nodeId: 'n', counter: 2),
          ),
        ];

        final result = await transport.push(ops);

        expect(result.success, isTrue);
        expect(result.acknowledgedIds, equals(['op_1']));
      });

      test('throws on non-200/201 response', () async {
        mockClient = MockClient((request) async {
          return http.Response('Bad Request', 400);
        });

        final transport = HttpTransport(
          baseUrl: 'https://api.test.com',
          nodeId: 'test_node',
          client: mockClient,
        );

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

        expect(
          () => transport.push(ops),
          throwsA(isA<HttpTransportException>()),
        );
      });

      test('accepts 201 response', () async {
        mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'accepted': ['op_1'],
            }),
            201,
          );
        });

        final transport = HttpTransport(
          baseUrl: 'https://api.test.com',
          nodeId: 'test_node',
          client: mockClient,
        );

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

        final result = await transport.push(ops);

        expect(result.success, isTrue);
      });

      test('defaults to all ops acknowledged if server omits accepted',
          () async {
        mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({}),
            200,
          );
        });

        final transport = HttpTransport(
          baseUrl: 'https://api.test.com',
          nodeId: 'test_node',
          client: mockClient,
        );

        final ops = [
          CreateOp(
            opId: 'op_1',
            recordId: 'rec_1',
            collection: 'test',
            payload: {},
            timestamp: 1000,
            clock: const LogicalClock(nodeId: 'n', counter: 1),
          ),
          CreateOp(
            opId: 'op_2',
            recordId: 'rec_2',
            collection: 'test',
            payload: {},
            timestamp: 2000,
            clock: const LogicalClock(nodeId: 'n', counter: 2),
          ),
        ];

        final result = await transport.push(ops);

        expect(result.acknowledgedIds, equals(['op_1', 'op_2']));
      });
    });

    test('close calls client.close', () {
      mockClient = MockClient((request) async {
        return http.Response('', 200);
      });

      // We can't easily test this without a real MockClient that tracks close
      // but we can verify the method exists and doesn't throw
      final transport = HttpTransport(
        baseUrl: 'https://api.test.com',
        nodeId: 'test_node',
        client: mockClient,
      );

      expect(() => transport.close(), returnsNormally);
    });
  });
}
