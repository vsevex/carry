import 'clock.dart';

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
        payload: json['payload'] as Map<String, dynamic>,
        timestamp: json['timestamp'] as int,
        clock: LogicalClock.fromJson(json['clock'] as Map<String, dynamic>),
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
        payload: json['payload'] as Map<String, dynamic>,
        baseVersion: json['baseVersion'] as int,
        timestamp: json['timestamp'] as int,
        clock: LogicalClock.fromJson(json['clock'] as Map<String, dynamic>),
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
        clock: LogicalClock.fromJson(json['clock'] as Map<String, dynamic>),
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

  factory ReconcileResult.fromJson(Map<String, dynamic> json) =>
      ReconcileResult(
        acceptedLocal: (json['acceptedLocal'] as List<dynamic>).cast<String>(),
        rejectedLocal: (json['rejectedLocal'] as List<dynamic>).cast<String>(),
        // Rust returns 'appliedRemote' for accepted remote ops
        acceptedRemote:
            (json['appliedRemote'] as List<dynamic>).cast<String>(),
        rejectedRemote:
            (json['rejectedRemote'] as List<dynamic>).cast<String>(),
        conflicts: (json['conflicts'] as List<dynamic>)
            .map((c) => Conflict.fromJson(c as Map<String, dynamic>))
            .toList(),
      );

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

  factory Conflict.fromJson(Map<String, dynamic> json) {
    final resolution = json['resolution'] as Map<String, dynamic>;
    return Conflict(
      recordId: json['recordId'] as String,
      collection: json['collection'] as String,
      localOpId: json['localOpId'] as String,
      remoteOpId: json['remoteOpId'] as String,
      resolution: resolution.keys.first,
      winnerId: resolution.values.first as String,
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
