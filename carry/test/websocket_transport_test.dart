import 'package:flutter_test/flutter_test.dart';

import 'package:carry/carry.dart';

void main() {
  group('WebSocketTransportException', () {
    test('creates with message', () {
      final ex = WebSocketTransportException('Connection failed');

      expect(ex.message, equals('Connection failed'));
    });

    test('toString returns formatted message', () {
      final ex = WebSocketTransportException('Timeout');

      expect(
        ex.toString(),
        equals('WebSocketTransportException: Timeout'),
      );
    });
  });

  group('WebSocketConnectionState', () {
    test('has all expected values', () {
      expect(WebSocketConnectionState.values, hasLength(4));
      expect(
        WebSocketConnectionState.values,
        containsAll([
          WebSocketConnectionState.disconnected,
          WebSocketConnectionState.connecting,
          WebSocketConnectionState.connected,
          WebSocketConnectionState.reconnecting,
        ]),
      );
    });
  });

  group('WebSocketTransport', () {
    test('creates with required parameters', () {
      final transport = WebSocketTransport(
        url: 'ws://localhost:8080/sync/ws',
        nodeId: 'device_1',
      );

      expect(transport.url, equals('ws://localhost:8080/sync/ws'));
      expect(transport.nodeId, equals('device_1'));
      expect(transport.isConnected, isFalse);
      expect(
        transport.currentState,
        equals(WebSocketConnectionState.disconnected),
      );
    });

    test('creates with custom parameters', () {
      final transport = WebSocketTransport(
        url: 'wss://api.example.com/sync/ws',
        nodeId: 'node_xyz',
        headers: {'Authorization': 'Bearer token123'},
        reconnectDelay: const Duration(seconds: 2),
        maxReconnectDelay: const Duration(seconds: 60),
        requestTimeout: const Duration(seconds: 45),
      );

      expect(transport.reconnectDelay, equals(const Duration(seconds: 2)));
      expect(transport.maxReconnectDelay, equals(const Duration(seconds: 60)));
      expect(transport.requestTimeout, equals(const Duration(seconds: 45)));
    });

    test('incomingOperations stream is broadcast', () {
      final transport = WebSocketTransport(
        url: 'ws://localhost:8080/sync/ws',
        nodeId: 'device_1',
      );

      // Should be able to listen multiple times without error
      final sub1 = transport.incomingOperations.listen((_) {});
      final sub2 = transport.incomingOperations.listen((_) {});

      expect(sub1, isNotNull);
      expect(sub2, isNotNull);

      sub1.cancel();
      sub2.cancel();
    });

    test('connectionState stream is broadcast', () {
      final transport = WebSocketTransport(
        url: 'ws://localhost:8080/sync/ws',
        nodeId: 'device_1',
      );

      final sub1 = transport.connectionState.listen((_) {});
      final sub2 = transport.connectionState.listen((_) {});

      expect(sub1, isNotNull);
      expect(sub2, isNotNull);

      sub1.cancel();
      sub2.cancel();
    });

    test('isConnected returns false initially', () {
      final transport = WebSocketTransport(
        url: 'ws://localhost:8080/sync/ws',
        nodeId: 'device_1',
      );

      expect(transport.isConnected, isFalse);
    });

    test('pull throws when not connected', () {
      final transport = WebSocketTransport(
        url: 'ws://localhost:8080/sync/ws',
        nodeId: 'device_1',
      );

      expect(
        () => transport.pull(null),
        throwsA(isA<WebSocketTransportException>()),
      );
    });

    test('push returns empty result for empty operations', () async {
      final transport = WebSocketTransport(
        url: 'ws://localhost:8080/sync/ws',
        nodeId: 'device_1',
      );

      // Empty operations should return success without connecting
      final result = await transport.push([]);

      expect(result.success, isTrue);
      expect(result.acknowledgedIds, isEmpty);
    });

    test('push throws when not connected with non-empty operations', () async {
      final transport = WebSocketTransport(
        url: 'ws://localhost:8080/sync/ws',
        nodeId: 'device_1',
      );

      final ops = [
        CreateOp(
          opId: 'op_1',
          recordId: 'rec_1',
          collection: 'test',
          payload: {'key': 'value'},
          timestamp: 1000,
          clock: const LogicalClock(nodeId: 'device_1', counter: 1),
        ),
      ];

      final result = await transport.push(ops);

      expect(result.success, isFalse);
      expect(result.error, contains('Not connected'));
    });

    test('close can be called multiple times safely', () async {
      final transport = WebSocketTransport(
        url: 'ws://localhost:8080/sync/ws',
        nodeId: 'device_1',
      );

      // Should not throw
      await transport.close();
      await transport.close();
    });

    test('disconnect sets state to disconnected', () async {
      final transport = WebSocketTransport(
        url: 'ws://localhost:8080/sync/ws',
        nodeId: 'device_1',
      );

      final states = <WebSocketConnectionState>[];
      transport.connectionState.listen(states.add);

      await transport.disconnect();

      // Allow stream to propagate
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        transport.currentState,
        equals(WebSocketConnectionState.disconnected),
      );
    });
  });

  group('WebSocketTransport integration with SyncStore', () {
    test('SyncStore detects WebSocket transport', () {
      final schema =
          Schema.v(1).collection('test', [Field.string('name')]).build();

      final wsTransport = WebSocketTransport(
        url: 'ws://localhost:8080/sync/ws',
        nodeId: 'device_1',
      );

      final store = SyncStore(
        schema: schema,
        nodeId: 'device_1',
        transport: wsTransport,
      );

      expect(store.hasWebSocketTransport, isTrue);
      expect(store.webSocketTransport, equals(wsTransport));
    });

    test('SyncStore with HTTP transport returns null webSocketTransport', () {
      final schema =
          Schema.v(1).collection('test', [Field.string('name')]).build();

      final httpTransport = HttpTransport(
        baseUrl: 'http://localhost:8080',
        nodeId: 'device_1',
      );

      final store = SyncStore(
        schema: schema,
        nodeId: 'device_1',
        transport: httpTransport,
      );

      expect(store.hasWebSocketTransport, isFalse);
      expect(store.webSocketTransport, isNull);
    });
  });
}
