import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'package:carry/carry.dart';

void main() {
  group('FilePersistenceAdapter', () {
    late Directory tempDir;
    late FilePersistenceAdapter adapter;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('carry_test_');
      adapter = FilePersistenceAdapter(directory: tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('creates with directory and default extension', () {
      expect(adapter.directory, equals(tempDir));
      expect(adapter.extension, equals('.json'));
    });

    test('creates with custom extension', () {
      final customAdapter = FilePersistenceAdapter(
        directory: tempDir,
        extension: '.dat',
      );

      expect(customAdapter.extension, equals('.dat'));
    });

    group('read', () {
      test('returns null for non-existent key', () async {
        final result = await adapter.read('nonexistent');
        expect(result, isNull);
      });

      test('reads previously written value', () async {
        await adapter.write('test_key', 'test_value');
        final result = await adapter.read('test_key');

        expect(result, equals('test_value'));
      });

      test('reads JSON data correctly', () async {
        const jsonData = '{"key": "value", "number": 42}';
        await adapter.write('json_key', jsonData);

        final result = await adapter.read('json_key');
        expect(result, equals(jsonData));
      });

      test('reads large data', () async {
        final largeData = 'x' * 100000;
        await adapter.write('large_key', largeData);

        final result = await adapter.read('large_key');
        expect(result, equals(largeData));
      });
    });

    group('write', () {
      test('writes to file', () async {
        await adapter.write('new_key', 'new_value');

        final file = File(path.join(tempDir.path, 'new_key.json'));
        expect(await file.exists(), isTrue);
        expect(await file.readAsString(), equals('new_value'));
      });

      test('overwrites existing value', () async {
        await adapter.write('overwrite_key', 'original');
        await adapter.write('overwrite_key', 'updated');

        final result = await adapter.read('overwrite_key');
        expect(result, equals('updated'));
      });

      test('creates directory if it does not exist', () async {
        await tempDir.delete(recursive: true);

        await adapter.write('recreate_key', 'value');

        expect(await tempDir.exists(), isTrue);
        final result = await adapter.read('recreate_key');
        expect(result, equals('value'));
      });

      test('sanitizes key for filesystem', () async {
        await adapter.write('key/with:special*chars?', 'value');

        // Should not contain special characters in filename
        final files = await tempDir.list().toList();
        expect(files.length, equals(1));

        final filename = path.basename((files.first as File).path);
        expect(filename.contains('/'), isFalse);
        expect(filename.contains(':'), isFalse);
        expect(filename.contains('*'), isFalse);
        expect(filename.contains('?'), isFalse);
      });

      test('handles empty string value', () async {
        await adapter.write('empty_key', '');

        final result = await adapter.read('empty_key');
        expect(result, equals(''));
      });

      test('handles unicode content', () async {
        const unicode = '你好世界 🌍 مرحبا';
        await adapter.write('unicode_key', unicode);

        final result = await adapter.read('unicode_key');
        expect(result, equals(unicode));
      });
    });

    group('delete', () {
      test('deletes existing key', () async {
        await adapter.write('delete_key', 'value');
        await adapter.delete('delete_key');

        final result = await adapter.read('delete_key');
        expect(result, isNull);
      });

      test('does nothing for non-existent key', () async {
        // Should not throw
        await adapter.delete('nonexistent_key');
      });

      test('removes file from disk', () async {
        await adapter.write('file_delete_key', 'value');
        final file = File(path.join(tempDir.path, 'file_delete_key.json'));

        expect(await file.exists(), isTrue);

        await adapter.delete('file_delete_key');

        expect(await file.exists(), isFalse);
      });
    });

    group('clear', () {
      test('removes all files with extension', () async {
        await adapter.write('key1', 'value1');
        await adapter.write('key2', 'value2');
        await adapter.write('key3', 'value3');

        await adapter.clear();

        expect(await adapter.read('key1'), isNull);
        expect(await adapter.read('key2'), isNull);
        expect(await adapter.read('key3'), isNull);
      });

      test('does not remove files with different extension', () async {
        await adapter.write('json_key', 'json_value');

        // Create a file with different extension
        final otherFile = File(path.join(tempDir.path, 'other.txt'));
        await otherFile.writeAsString('other content');

        await adapter.clear();

        expect(await adapter.read('json_key'), isNull);
        expect(await otherFile.exists(), isTrue);
      });

      test('handles non-existent directory', () async {
        await tempDir.delete(recursive: true);

        // Should not throw
        await adapter.clear();
      });

      test('handles empty directory', () async {
        // Directory exists but has no files
        await adapter.clear();
        // Should not throw
      });
    });

    group('create factory', () {
      test('creates adapter with subdirectory', () async {
        final baseDir = await Directory.systemTemp.createTemp('carry_base_');
        try {
          final createdAdapter = await FilePersistenceAdapter.create(
            baseDirectory: baseDir,
            subdirectory: 'my_data',
          );

          final expectedDir = Directory(path.join(baseDir.path, 'my_data'));
          expect(await expectedDir.exists(), isTrue);
          expect(createdAdapter.directory.path, equals(expectedDir.path));
        } finally {
          await baseDir.delete(recursive: true);
        }
      });

      test('uses default subdirectory name', () async {
        final baseDir = await Directory.systemTemp.createTemp('carry_base_');
        try {
          final createdAdapter = await FilePersistenceAdapter.create(
            baseDirectory: baseDir,
          );

          final expectedDir = Directory(path.join(baseDir.path, 'carry_data'));
          expect(await expectedDir.exists(), isTrue);
          expect(createdAdapter.directory.path, equals(expectedDir.path));
        } finally {
          await baseDir.delete(recursive: true);
        }
      });

      test('creates nested directories', () async {
        final baseDir = await Directory.systemTemp.createTemp('carry_base_');
        try {
          final createdAdapter = await FilePersistenceAdapter.create(
            baseDirectory: baseDir,
            subdirectory: 'level1/level2/level3',
          );

          expect(await createdAdapter.directory.exists(), isTrue);
        } finally {
          await baseDir.delete(recursive: true);
        }
      });
    });

    group('concurrent operations', () {
      test('handles concurrent writes to different keys', () async {
        await Future.wait([
          adapter.write('concurrent1', 'value1'),
          adapter.write('concurrent2', 'value2'),
          adapter.write('concurrent3', 'value3'),
        ]);

        expect(await adapter.read('concurrent1'), equals('value1'));
        expect(await adapter.read('concurrent2'), equals('value2'));
        expect(await adapter.read('concurrent3'), equals('value3'));
      });

      test('handles concurrent writes to same key', () async {
        // This tests that the last write wins
        await Future.wait([
          adapter.write('same_key', 'value1'),
          adapter.write('same_key', 'value2'),
          adapter.write('same_key', 'value3'),
        ]);

        final result = await adapter.read('same_key');
        // Result should be one of the values (implementation dependent)
        expect(['value1', 'value2', 'value3'].contains(result), isTrue);
      });

      test('handles concurrent read and write', () async {
        await adapter.write('rw_key', 'initial');

        final results = await Future.wait([
          adapter.read('rw_key'),
          adapter.write('rw_key', 'updated').then((_) => 'write_done'),
        ]);

        // Read might get initial or updated value
        expect(results[0], anyOf(equals('initial'), equals('updated'), isNull));
      });
    });

    group('edge cases', () {
      test('handles very long key names', () async {
        final longKey = 'a' * 200;
        await adapter.write(longKey, 'value');

        final result = await adapter.read(longKey);
        expect(result, equals('value'));
      });

      test('handles key with only special characters', () async {
        await adapter.write('!@#\$%^&*()', 'special_value');

        final result = await adapter.read('!@#\$%^&*()');
        expect(result, equals('special_value'));
      });

      test('handles newlines in value', () async {
        const multiline = 'line1\nline2\nline3';
        await adapter.write('multiline_key', multiline);

        final result = await adapter.read('multiline_key');
        expect(result, equals(multiline));
      });

      test('handles binary-like content', () async {
        // Note: This is still a string, but with bytes that might cause issues
        final binaryLike = String.fromCharCodes(
          List.generate(256, (i) => i),
        );
        await adapter.write('binary_key', binaryLike);

        final result = await adapter.read('binary_key');
        expect(result, equals(binaryLike));
      });
    });
  });
}
