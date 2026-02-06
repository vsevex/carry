import 'dart:io';

import 'package:path/path.dart' as path;

import 'persistence_adapter.dart';

/// File-based persistence adapter.
///
/// Stores each key as a separate file in the specified directory.
/// This is a simple reference implementation suitable for many use cases.
///
/// ```dart
/// final adapter = FilePersistenceAdapter(
///   directory: await getApplicationDocumentsDirectory(),
/// );
/// ```
class FilePersistenceAdapter implements PersistenceAdapter {
  FilePersistenceAdapter({
    required this.directory,
    this.extension = '.json',
  });

  /// The directory to store files in.
  final Directory directory;

  /// File extension for storage files.
  final String extension;

  /// Create a file adapter using the app's documents directory.
  ///
  /// Creates a subdirectory named [subdirectory] within the provided
  /// base directory.
  static Future<FilePersistenceAdapter> create({
    required Directory baseDirectory,
    String subdirectory = 'carry_data',
  }) async {
    final directory = Directory(path.join(baseDirectory.path, subdirectory));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return FilePersistenceAdapter(directory: directory);
  }

  File _fileForKey(String key) {
    // Sanitize key for filesystem
    final sanitized = key.replaceAll(RegExp(r'[^\w\-]'), '_');
    return File(path.join(directory.path, '$sanitized$extension'));
  }

  @override
  Future<String?> read(String key) async {
    final file = _fileForKey(key);
    if (await file.exists()) {
      return await file.readAsString();
    }
    return null;
  }

  @override
  Future<void> write(String key, String value) async {
    // Ensure directory exists
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final file = _fileForKey(key);
    await file.writeAsString(value);
  }

  @override
  Future<void> delete(String key) async {
    final file = _fileForKey(key);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<void> clear() async {
    if (await directory.exists()) {
      await for (final entity in directory.list()) {
        if (entity is File && entity.path.endsWith(extension)) {
          await entity.delete();
        }
      }
    }
  }
}
