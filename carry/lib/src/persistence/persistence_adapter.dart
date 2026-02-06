/// Interface for persistence.
///
/// Implement this interface to provide custom storage for your app.
/// The SDK includes [FilePersistenceAdapter] as a reference implementation.
abstract interface class PersistenceAdapter {
  /// Read a value by key.
  ///
  /// Returns null if the key doesn't exist.
  Future<String?> read(String key);

  /// Write a value by key.
  ///
  /// Overwrites any existing value.
  Future<void> write(String key, String value);

  /// Delete a value by key.
  ///
  /// Does nothing if the key doesn't exist.
  Future<void> delete(String key);

  /// Clear all stored values.
  Future<void> clear();
}
