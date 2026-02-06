import 'clock.dart';

/// Origin of a record or operation.
enum Origin {
  local,
  remote;

  factory Origin.fromJson(String json) {
    return Origin.values.firstWhere((e) => e.name == json.toLowerCase());
  }

  String toJson() => name;
}

/// Metadata attached to every record.
class Metadata {
  Metadata({
    required this.createdAt,
    required this.updatedAt,
    required this.origin,
    required this.clock,
  });

  factory Metadata.fromJson(Map<String, dynamic> json) {
    return Metadata(
      createdAt: json['createdAt'] as int,
      updatedAt: json['updatedAt'] as int,
      origin: Origin.fromJson(json['origin'] as String),
      clock: LogicalClock.fromJson(json['clock'] as Map<String, dynamic>),
    );
  }

  /// When the record was created.
  final int createdAt;

  /// When the record was last updated.
  final int updatedAt;

  /// Origin of the last modification.
  final Origin origin;

  /// Logical clock for ordering.
  final LogicalClock clock;

  Map<String, dynamic> toJson() => {
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'origin': origin.toJson(),
        'clock': clock.toJson(),
      };
}

/// A data record in the store.
class Record {
  Record({
    required this.id,
    required this.collection,
    required this.version,
    required this.payload,
    required this.metadata,
    required this.deleted,
  });

  factory Record.fromJson(Map<String, dynamic> json) {
    return Record(
      id: json['id'] as String,
      collection: json['collection'] as String,
      version: json['version'] as int,
      payload: json['payload'] as Map<String, dynamic>,
      metadata: Metadata.fromJson(json['metadata'] as Map<String, dynamic>),
      deleted: json['deleted'] as bool,
    );
  }

  /// Unique identifier.
  final String id;

  /// Collection this record belongs to.
  final String collection;

  /// Version number (incremented on each update).
  final int version;

  /// The data payload.
  final Map<String, dynamic> payload;

  /// Record metadata.
  final Metadata metadata;

  /// Whether this record is deleted (tombstone).
  final bool deleted;

  Map<String, dynamic> toJson() => {
        'id': id,
        'collection': collection,
        'version': version,
        'payload': payload,
        'metadata': metadata.toJson(),
        'deleted': deleted,
      };

  /// Whether this record is active (not deleted).
  bool get isActive => !deleted;

  /// Get the creation timestamp.
  int get createdAt => metadata.createdAt;

  /// Get the last update timestamp.
  int get updatedAt => metadata.updatedAt;

  @override
  String toString() =>
      'Record($collection/$id v$version${deleted ? ' [deleted]' : ''})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Record &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          collection == other.collection &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ collection.hashCode ^ version.hashCode;
}
