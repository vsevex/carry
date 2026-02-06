import 'package:flutter_test/flutter_test.dart';

import 'package:carry/carry.dart';

void main() {
  group('LogicalClock', () {
    test('creates with nodeId and counter', () {
      const clock = LogicalClock(nodeId: 'device_1', counter: 0);

      expect(clock.nodeId, equals('device_1'));
      expect(clock.counter, equals(0));
    });

    test('tick increments counter', () {
      const clock = LogicalClock(nodeId: 'node1', counter: 5);
      final ticked = clock.tick();

      expect(ticked.counter, equals(6));
      expect(ticked.nodeId, equals('node1'));
    });

    test('tick preserves nodeId', () {
      const clock = LogicalClock(nodeId: 'special_node', counter: 100);
      final ticked = clock.tick();

      expect(ticked.nodeId, equals('special_node'));
    });

    test('tick does not mutate original', () {
      final clock = const LogicalClock(nodeId: 'node1', counter: 0)..tick();

      expect(clock.counter, equals(0));
    });

    test('multiple ticks chain correctly', () {
      const clock = LogicalClock(nodeId: 'n', counter: 0);
      final result = clock.tick().tick().tick();

      expect(result.counter, equals(3));
    });

    test('toJson serializes correctly', () {
      const clock = LogicalClock(nodeId: 'device_abc', counter: 42);
      final json = clock.toJson();

      expect(json['nodeId'], equals('device_abc'));
      expect(json['counter'], equals(42));
    });

    test('fromJson parses correctly', () {
      final json = {'nodeId': 'parsed_node', 'counter': 123};
      final clock = LogicalClock.fromJson(json);

      expect(clock.nodeId, equals('parsed_node'));
      expect(clock.counter, equals(123));
    });

    test('round-trip serialization preserves data', () {
      const original = LogicalClock(nodeId: 'test_node', counter: 999);
      final json = original.toJson();
      final restored = LogicalClock.fromJson(json);

      expect(restored.nodeId, equals(original.nodeId));
      expect(restored.counter, equals(original.counter));
    });

    test('toString formats correctly', () {
      const clock = LogicalClock(nodeId: 'my_node', counter: 10);
      expect(clock.toString(), equals('LogicalClock(my_node:10)'));
    });

    test('equality works for same values', () {
      const clock1 = LogicalClock(nodeId: 'node', counter: 5);
      const clock2 = LogicalClock(nodeId: 'node', counter: 5);

      expect(clock1 == clock2, isTrue);
      expect(clock1.hashCode, equals(clock2.hashCode));
    });

    test('equality fails for different nodeId', () {
      const clock1 = LogicalClock(nodeId: 'node1', counter: 5);
      const clock2 = LogicalClock(nodeId: 'node2', counter: 5);

      expect(clock1 == clock2, isFalse);
    });

    test('equality fails for different counter', () {
      const clock1 = LogicalClock(nodeId: 'node', counter: 5);
      const clock2 = LogicalClock(nodeId: 'node', counter: 6);

      expect(clock1 == clock2, isFalse);
    });

    test('handles empty nodeId', () {
      const clock = LogicalClock(nodeId: '', counter: 0);
      expect(clock.nodeId, equals(''));

      final json = clock.toJson();
      final restored = LogicalClock.fromJson(json);
      expect(restored.nodeId, equals(''));
    });

    test('handles large counter values', () {
      const clock = LogicalClock(nodeId: 'node', counter: 9223372036854775807);
      expect(clock.counter, equals(9223372036854775807));
    });

    test('handles special characters in nodeId', () {
      const clock = LogicalClock(
        nodeId: 'device-123_abc@example.com',
        counter: 1,
      );
      final json = clock.toJson();
      final restored = LogicalClock.fromJson(json);

      expect(restored.nodeId, equals('device-123_abc@example.com'));
    });
  });
}
