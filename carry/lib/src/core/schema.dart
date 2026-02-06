/// Field types supported in schemas.
enum FieldType {
  string,
  int_,
  float_,
  bool_,
  timestamp,
  json;

  String toJson() {
    switch (this) {
      case FieldType.string:
        return 'string';
      case FieldType.int_:
        return 'int';
      case FieldType.float_:
        return 'float';
      case FieldType.bool_:
        return 'bool';
      case FieldType.timestamp:
        return 'timestamp';
      case FieldType.json:
        return 'json';
    }
  }
}

/// Definition of a field in a collection.
class Field {
  /// Create a JSON field (arbitrary nested data).
  factory Field.json(String name, {bool required = false}) =>
      Field._(name: name, type: FieldType.json, required: required);

  /// Create a timestamp field.
  factory Field.timestamp(String name, {bool required = false}) =>
      Field._(name: name, type: FieldType.timestamp, required: required);

  /// Create a boolean field.
  factory Field.bool_(String name, {bool required = false}) =>
      Field._(name: name, type: FieldType.bool_, required: required);

  /// Create a float field.
  factory Field.float_(String name, {bool required = false}) =>
      Field._(name: name, type: FieldType.float_, required: required);

  /// Create an integer field.
  factory Field.int_(String name, {bool required = false}) =>
      Field._(name: name, type: FieldType.int_, required: required);

  /// Create a required string field.
  factory Field.string(String name, {bool required = false}) =>
      Field._(name: name, type: FieldType.string, required: required);

  const Field._({
    required this.name,
    required this.type,
    required this.required,
  });

  /// Field name.
  final String name;

  /// Field type.
  final FieldType type;

  /// Whether this field is required.
  final bool required;

  Map<String, dynamic> toJson() => {
        'name': name,
        'fieldType': type.toJson(),
        'required': required,
      };
}

/// Schema for a collection.
class CollectionSchema {
  const CollectionSchema({
    required this.name,
    required this.fields,
  });

  /// Collection name.
  final String name;

  /// Field definitions.
  final List<Field> fields;

  Map<String, dynamic> toJson() => {
        'name': name,
        'fields': fields.map((f) => f.toJson()).toList(),
      };
}

/// Builder for creating schemas.
class SchemaBuilder {
  SchemaBuilder._(this._version);

  final int _version;
  final List<CollectionSchema> _collections = [];

  /// Add a collection to the schema.
  SchemaBuilder collection(String name, List<Field> fields) {
    _collections.add(CollectionSchema(name: name, fields: fields));
    return this;
  }

  /// Build the schema.
  Schema build() => Schema._(
        version: _version,
        collections: Map.fromEntries(
          _collections.map((c) => MapEntry(c.name, c)),
        ),
      );
}

/// Schema for the entire store.
class Schema {
  /// Create a schema from JSON.
  factory Schema.fromJson(Map<String, dynamic> json) {
    final collections = (json['collections'] as Map<String, dynamic>).map(
      (name, value) {
        final collectionJson = value as Map<String, dynamic>;
        final fields = (collectionJson['fields'] as List<dynamic>).map((f) {
          final fieldJson = f as Map<String, dynamic>;
          final type = _parseFieldType(fieldJson['fieldType'] as String);
          return Field._(
            name: fieldJson['name'] as String,
            type: type,
            required: fieldJson['required'] as bool,
          );
        }).toList();
        return MapEntry(name, CollectionSchema(name: name, fields: fields));
      },
    );

    return Schema._(
      version: json['version'] as int,
      collections: collections,
    );
  }

  Schema._({
    required this.version,
    required this.collections,
  });

  /// Schema version for migrations.
  final int version;

  /// Collection schemas by name.
  final Map<String, CollectionSchema> collections;

  /// Start building a schema with the given version.
  static SchemaBuilder v(int version) => SchemaBuilder._(version);

  /// Get a collection schema by name.
  CollectionSchema? operator [](String name) => collections[name];

  /// Check if a collection exists.
  bool hasCollection(String name) => collections.containsKey(name);

  /// Get all collection names.
  Iterable<String> get collectionNames => collections.keys;

  /// Convert to JSON for FFI.
  Map<String, dynamic> toJson() => {
        'version': version,
        'collections': Map.fromEntries(
          collections.entries.map((e) => MapEntry(e.key, e.value.toJson())),
        ),
      };

  static FieldType _parseFieldType(String type) {
    switch (type) {
      case 'string':
        return FieldType.string;
      case 'int':
        return FieldType.int_;
      case 'float':
        return FieldType.float_;
      case 'bool':
        return FieldType.bool_;
      case 'timestamp':
        return FieldType.timestamp;
      case 'json':
        return FieldType.json;
      default:
        throw ArgumentError('Unknown field type: $type');
    }
  }
}
