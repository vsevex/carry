import 'dart:convert';

/// Safely convert a value that may be a [Map] or a JSON-encoded [String]
/// into a [Map<String, dynamic>].
///
/// This is needed because the Rust FFI layer may return nested objects as
/// JSON strings within the outer decoded JSON structure.
Map<String, dynamic> asJsonMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  if (value is String) {
    return Map<String, dynamic>.from(jsonDecode(value) as Map);
  }
  throw StateError('Expected Map or JSON String, got ${value.runtimeType}');
}

/// Logical clock for causal ordering of operations.
class LogicalClock {
  const LogicalClock({
    required this.nodeId,
    required this.counter,
  });

  /// Create a clock from JSON.
  factory LogicalClock.fromJson(Map<String, dynamic> json) => LogicalClock(
        nodeId: json['nodeId'] as String,
        counter: json['counter'] as int,
      );

  /// The node ID that owns this clock.
  final String nodeId;

  /// The counter value.
  final int counter;

  /// Convert to JSON for FFI.
  Map<String, dynamic> toJson() => {
        'nodeId': nodeId,
        'counter': counter,
      };

  /// Create a new clock with counter incremented.
  LogicalClock tick() => LogicalClock(
        nodeId: nodeId,
        counter: counter + 1,
      );

  @override
  String toString() => 'LogicalClock($nodeId:$counter)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LogicalClock &&
          runtimeType == other.runtimeType &&
          nodeId == other.nodeId &&
          counter == other.counter;

  @override
  int get hashCode => nodeId.hashCode ^ counter.hashCode;
}
