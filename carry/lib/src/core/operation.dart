import 'clock.dart' show LogicalClock, asJsonMap;

/// Base class for all operations.
sealed class Operation {
  /// Unique identifier for this operation.
  String get opId;

  /// The record this operation targets.
  String get recordId;

  /// The collection this operation targets.
  String get collection;

  /// Timestamp when this operation was created.
  int get timestamp;

  /// Logical clock for ordering.
  LogicalClock get clock;

  /// Convert to JSON for FFI.
  Map<String, dynamic> toJson();

  /// Create an operation from JSON.
  static Operation fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    switch (type) {
      case 'create':
        return CreateOp.fromJson(json);
      case 'update':
        return UpdateOp.fromJson(json);
      case 'delete':
        return DeleteOp.fromJson(json);
      default:
        throw ArgumentError('Unknown operation type: $type');
    }
  }
}

/// Operation to create a new record.
class CreateOp extends Operation {
  CreateOp({
    required this.opId,
    required this.recordId,
    required this.collection,
    required this.payload,
    required this.timestamp,
    required this.clock,
  });

  factory CreateOp.fromJson(Map<String, dynamic> json) => CreateOp(
        opId: json['opId'] as String,
        recordId: json['id'] as String,
        collection: json['collection'] as String,
        payload: asJsonMap(json['payload']),
        timestamp: json['timestamp'] as int,
        clock: LogicalClock.fromJson(asJsonMap(json['clock'])),
      );
  @override
  final String opId;

  @override
  final String recordId;

  @override
  final String collection;

  /// The initial payload for the record.
  final Map<String, dynamic> payload;

  @override
  final int timestamp;

  @override
  final LogicalClock clock;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'create',
        'opId': opId,
        'id': recordId,
        'collection': collection,
        'payload': payload,
        'timestamp': timestamp,
        'clock': clock.toJson(),
      };
}

/// Operation to update an existing record.
class UpdateOp extends Operation {
  UpdateOp({
    required this.opId,
    required this.recordId,
    required this.collection,
    required this.payload,
    required this.baseVersion,
    required this.timestamp,
    required this.clock,
  });

  factory UpdateOp.fromJson(Map<String, dynamic> json) => UpdateOp(
        opId: json['opId'] as String,
        recordId: json['id'] as String,
        collection: json['collection'] as String,
        payload: asJsonMap(json['payload']),
        baseVersion: json['baseVersion'] as int,
        timestamp: json['timestamp'] as int,
        clock: LogicalClock.fromJson(asJsonMap(json['clock'])),
      );

  @override
  final String opId;

  @override
  final String recordId;

  @override
  final String collection;

  /// The new payload (full replacement).
  final Map<String, dynamic> payload;

  /// The version this update is based on.
  final int baseVersion;

  @override
  final int timestamp;

  @override
  final LogicalClock clock;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'update',
        'opId': opId,
        'id': recordId,
        'collection': collection,
        'payload': payload,
        'baseVersion': baseVersion,
        'timestamp': timestamp,
        'clock': clock.toJson(),
      };
}

/// Operation to delete a record (soft delete).
class DeleteOp extends Operation {
  DeleteOp({
    required this.opId,
    required this.recordId,
    required this.collection,
    required this.baseVersion,
    required this.timestamp,
    required this.clock,
  });

  factory DeleteOp.fromJson(Map<String, dynamic> json) => DeleteOp(
        opId: json['opId'] as String,
        recordId: json['id'] as String,
        collection: json['collection'] as String,
        baseVersion: json['baseVersion'] as int,
        timestamp: json['timestamp'] as int,
        clock: LogicalClock.fromJson(asJsonMap(json['clock'])),
      );

  @override
  final String opId;

  @override
  final String recordId;

  @override
  final String collection;

  /// The version this delete is based on.
  final int baseVersion;

  @override
  final int timestamp;

  @override
  final LogicalClock clock;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'delete',
        'opId': opId,
        'id': recordId,
        'collection': collection,
        'baseVersion': baseVersion,
        'timestamp': timestamp,
        'clock': clock.toJson(),
      };

  /// For DeleteOp, payload is empty.
  Map<String, dynamic> get payload => const {};
}

/// Result of applying an operation.
class ApplyResult {
  ApplyResult({
    required this.opId,
    required this.recordId,
    required this.version,
  });

  factory ApplyResult.fromJson(Map<String, dynamic> json) => ApplyResult(
        opId: json['opId'] as String,
        recordId: json['recordId'] as String,
        version: json['version'] as int,
      );

  /// The operation ID.
  final String opId;

  /// The record ID.
  final String recordId;

  /// The new version after applying.
  final int version;
}

/// Result of reconciliation.
class ReconcileResult {
  ReconcileResult({
    required this.acceptedLocal,
    required this.rejectedLocal,
    required this.acceptedRemote,
    required this.rejectedRemote,
    required this.conflicts,
  });

  factory ReconcileResult.fromJson(Map<String, dynamic> json) {
    // Helper to safely extract a list of Strings, handling null or missing keys
    List<String> stringList(String key) =>
        (json[key] as List<dynamic>?)?.whereType<String>().toList() ?? const [];

    return ReconcileResult(
      acceptedLocal: stringList('acceptedLocal'),
      rejectedLocal: stringList('rejectedLocal'),
      // Rust returns 'appliedRemote' for accepted remote ops
      acceptedRemote: stringList('appliedRemote'),
      rejectedRemote: stringList('rejectedRemote'),
      conflicts: (json['conflicts'] as List<dynamic>?)
              ?.map((c) => Conflict.fromJson(asJsonMap(c)))
              .toList() ??
          const [],
    );
  }

  /// Operation IDs that were accepted from local.
  final List<String> acceptedLocal;

  /// Operation IDs that were rejected from local.
  final List<String> rejectedLocal;

  /// Operation IDs that were accepted from remote.
  final List<String> acceptedRemote;

  /// Operation IDs that were rejected from remote.
  final List<String> rejectedRemote;

  /// Conflicts that were resolved.
  final List<Conflict> conflicts;
}

/// A conflict between local and remote operations.
class Conflict {
  Conflict({
    required this.recordId,
    required this.collection,
    required this.localOpId,
    required this.remoteOpId,
    required this.resolution,
    required this.winnerId,
  });

  /// Parse a conflict from the Rust engine JSON.
  ///
  /// The engine serializes conflicts as:
  /// ```json
  /// {
  ///   "localOp":   { "type": "create", "opId": "...", "id": "...", "collection": "...", ... },
  ///   "remoteOp":  { "type": "create", "opId": "...", "id": "...", "collection": "...", ... },
  ///   "resolution": "localWins" | "remoteWins",
  ///   "winnerOpId": "..."
  /// }
  /// ```
  factory Conflict.fromJson(Map<String, dynamic> json) {
    // Parse the full operation objects sent by the engine
    final localOpRaw = asJsonMap(json['localOp']);
    final remoteOpRaw = asJsonMap(json['remoteOp']);

    // Extract record ID and collection from either operation
    final recordId = (localOpRaw['id'] ?? remoteOpRaw['id'] ?? '') as String;
    final collection =
        (localOpRaw['collection'] ?? remoteOpRaw['collection'] ?? '') as String;

    // Extract operation IDs
    final localOpId = (localOpRaw['opId'] ?? '') as String;
    final remoteOpId = (remoteOpRaw['opId'] ?? '') as String;

    // Parse resolution - can be a camelCase string like "localWins"
    final raw = json['resolution'];
    String resolution;
    if (raw is Map) {
      resolution = (raw).keys.first as String;
    } else if (raw is String) {
      resolution = raw;
    } else {
      resolution = raw?.toString() ?? 'unknown';
    }

    // Winner operation ID
    final winnerId = (json['winnerOpId'] ?? '') as String;

    return Conflict(
      recordId: recordId,
      collection: collection,
      localOpId: localOpId,
      remoteOpId: remoteOpId,
      resolution: resolution,
      winnerId: winnerId,
    );
  }

  /// The record ID.
  final String recordId;

  /// The collection.
  final String collection;

  /// The local operation ID.
  final String localOpId;

  /// The remote operation ID.
  final String remoteOpId;

  /// How the conflict was resolved.
  final String resolution;

  /// The winning operation ID.
  final String winnerId;
}
