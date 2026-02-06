import 'package:flutter_test/flutter_test.dart';

import 'package:carry/carry.dart';

void main() {
  group('FieldType', () {
    test('toJson returns correct string for all types', () {
      expect(FieldType.string.toJson(), equals('string'));
      expect(FieldType.int_.toJson(), equals('int'));
      expect(FieldType.float_.toJson(), equals('float'));
      expect(FieldType.bool_.toJson(), equals('bool'));
      expect(FieldType.timestamp.toJson(), equals('timestamp'));
      expect(FieldType.json.toJson(), equals('json'));
    });
  });

  group('Field', () {
    test('creates string field with required flag', () {
      final field = Field.string('name', required: true);
      expect(field.name, equals('name'));
      expect(field.type, equals(FieldType.string));
      expect(field.required, isTrue);
    });

    test('creates string field with optional flag (default)', () {
      final field = Field.string('name');
      expect(field.required, isFalse);
    });

    test('creates int field', () {
      final field = Field.int_('age', required: true);
      expect(field.name, equals('age'));
      expect(field.type, equals(FieldType.int_));
      expect(field.required, isTrue);
    });

    test('creates float field', () {
      final field = Field.float_('price');
      expect(field.name, equals('price'));
      expect(field.type, equals(FieldType.float_));
      expect(field.required, isFalse);
    });

    test('creates bool field', () {
      final field = Field.bool_('active');
      expect(field.name, equals('active'));
      expect(field.type, equals(FieldType.bool_));
    });

    test('creates timestamp field', () {
      final field = Field.timestamp('createdAt', required: true);
      expect(field.name, equals('createdAt'));
      expect(field.type, equals(FieldType.timestamp));
      expect(field.required, isTrue);
    });

    test('creates json field', () {
      final field = Field.json('metadata');
      expect(field.name, equals('metadata'));
      expect(field.type, equals(FieldType.json));
    });

    test('toJson serializes correctly', () {
      final field = Field.string('name', required: true);
      final json = field.toJson();

      expect(json['name'], equals('name'));
      expect(json['fieldType'], equals('string'));
      expect(json['required'], isTrue);
    });

    test('toJson serializes all field types', () {
      expect(
        Field.int_('age').toJson()['fieldType'],
        equals('int'),
      );
      expect(
        Field.float_('price').toJson()['fieldType'],
        equals('float'),
      );
      expect(
        Field.bool_('active').toJson()['fieldType'],
        equals('bool'),
      );
      expect(
        Field.timestamp('date').toJson()['fieldType'],
        equals('timestamp'),
      );
      expect(
        Field.json('data').toJson()['fieldType'],
        equals('json'),
      );
    });
  });

  group('CollectionSchema', () {
    test('creates with name and fields', () {
      final schema = CollectionSchema(
        name: 'users',
        fields: [
          Field.string('name', required: true),
          Field.int_('age'),
        ],
      );

      expect(schema.name, equals('users'));
      expect(schema.fields.length, equals(2));
    });

    test('toJson serializes correctly', () {
      final schema = CollectionSchema(
        name: 'posts',
        fields: [
          Field.string('title', required: true),
          Field.string('body'),
        ],
      );

      final json = schema.toJson();

      expect(json['name'], equals('posts'));
      expect(json['fields'], isA<List>());
      expect((json['fields'] as List).length, equals(2));
    });

    test('handles empty fields list', () {
      const schema = CollectionSchema(name: 'empty', fields: []);

      final json = schema.toJson();
      expect(json['fields'], isEmpty);
    });
  });

  group('SchemaBuilder', () {
    test('builds schema with single collection', () {
      final schema = Schema.v(1).collection('users', [
        Field.string('name', required: true),
      ]).build();

      expect(schema.version, equals(1));
      expect(schema.hasCollection('users'), isTrue);
      expect(schema.collectionNames, contains('users'));
    });

    test('builds schema with multiple collections', () {
      final schema = Schema.v(2)
          .collection('users', [Field.string('name')]).collection('posts', [
        Field.string('title'),
      ]).collection('comments', [Field.string('body')]).build();

      expect(schema.version, equals(2));
      expect(schema.collectionNames.length, equals(3));
      expect(schema.hasCollection('users'), isTrue);
      expect(schema.hasCollection('posts'), isTrue);
      expect(schema.hasCollection('comments'), isTrue);
    });

    test('chaining returns same builder', () {
      final builder = Schema.v(1);
      final returned = builder.collection('test', []);
      expect(identical(builder, returned), isTrue);
    });
  });

  group('Schema', () {
    test('v() creates builder with version', () {
      final schema = Schema.v(5).build();
      expect(schema.version, equals(5));
    });

    test('hasCollection returns true for existing collection', () {
      final schema = Schema.v(1).collection('users', []).build();

      expect(schema.hasCollection('users'), isTrue);
    });

    test('hasCollection returns false for non-existing collection', () {
      final schema = Schema.v(1).collection('users', []).build();

      expect(schema.hasCollection('posts'), isFalse);
    });

    test('operator[] returns collection schema', () {
      final schema =
          Schema.v(1).collection('users', [Field.string('name')]).build();

      final usersSchema = schema['users'];
      expect(usersSchema, isNotNull);
      expect(usersSchema!.name, equals('users'));
    });

    test('operator[] returns null for non-existing collection', () {
      final schema = Schema.v(1).build();
      expect(schema['nonexistent'], isNull);
    });

    test('collectionNames returns all collection names', () {
      final schema = Schema.v(1)
          .collection('a', []).collection('b', []).collection('c', []).build();

      expect(schema.collectionNames, containsAll(['a', 'b', 'c']));
    });

    test('toJson serializes version and collections', () {
      final schema = Schema.v(3).collection('items', [
        Field.string('name', required: true),
        Field.int_('quantity'),
      ]).build();

      final json = schema.toJson();

      expect(json['version'], equals(3));
      expect(json['collections'], isA<Map>());
      expect(json['collections']['items'], isNotNull);
    });

    test('fromJson parses schema correctly', () {
      final json = {
        'version': 2,
        'collections': {
          'users': {
            'name': 'users',
            'fields': [
              {'name': 'name', 'fieldType': 'string', 'required': true},
              {'name': 'age', 'fieldType': 'int', 'required': false},
            ],
          },
        },
      };

      final schema = Schema.fromJson(json);

      expect(schema.version, equals(2));
      expect(schema.hasCollection('users'), isTrue);
      expect(schema['users']!.fields.length, equals(2));
      expect(schema['users']!.fields[0].name, equals('name'));
      expect(schema['users']!.fields[0].type, equals(FieldType.string));
      expect(schema['users']!.fields[0].required, isTrue);
    });

    test('fromJson parses all field types', () {
      final json = {
        'version': 1,
        'collections': {
          'test': {
            'name': 'test',
            'fields': [
              {'name': 'f1', 'fieldType': 'string', 'required': false},
              {'name': 'f2', 'fieldType': 'int', 'required': false},
              {'name': 'f3', 'fieldType': 'float', 'required': false},
              {'name': 'f4', 'fieldType': 'bool', 'required': false},
              {'name': 'f5', 'fieldType': 'timestamp', 'required': false},
              {'name': 'f6', 'fieldType': 'json', 'required': false},
            ],
          },
        },
      };

      final schema = Schema.fromJson(json);
      final fields = schema['test']!.fields;

      expect(fields[0].type, equals(FieldType.string));
      expect(fields[1].type, equals(FieldType.int_));
      expect(fields[2].type, equals(FieldType.float_));
      expect(fields[3].type, equals(FieldType.bool_));
      expect(fields[4].type, equals(FieldType.timestamp));
      expect(fields[5].type, equals(FieldType.json));
    });

    test('fromJson throws on unknown field type', () {
      final json = {
        'version': 1,
        'collections': {
          'test': {
            'name': 'test',
            'fields': [
              {'name': 'f1', 'fieldType': 'unknown', 'required': false},
            ],
          },
        },
      };

      expect(() => Schema.fromJson(json), throwsArgumentError);
    });

    test('round-trip serialization preserves data', () {
      final original = Schema.v(1).collection('users', [
        Field.string('name', required: true),
        Field.int_('age'),
        Field.bool_('active'),
        Field.json('metadata'),
      ]).build();

      final json = original.toJson();
      final restored = Schema.fromJson(json);

      expect(restored.version, equals(original.version));
      expect(
        restored.collectionNames.toList(),
        equals(original.collectionNames.toList()),
      );
      expect(
        restored['users']!.fields.length,
        equals(original['users']!.fields.length),
      );
    });
  });
}
