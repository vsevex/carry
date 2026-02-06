/// Carry - A local-first data cache and sync layer for Flutter apps.
///
/// Carry provides offline-first data synchronization with a deterministic
/// Rust core. Your app works offline by default, feels fast on bad networks,
/// and syncs seamlessly when online.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:carry/carry.dart';
///
/// // 1. Define your schema
/// final schema = Schema.v(1)
///   .collection('users', [
///     Field.string('name', required: true),
///     Field.string('email'),
///   ])
///   .build();
///
/// // 2. Create a store
/// final store = SyncStore(
///   schema: schema,
///   nodeId: 'device_1',
///   persistence: FilePersistenceAdapter(directory: appDir),
///   transport: HttpTransport(baseUrl: 'https://api.example.com'),
/// );
///
/// await store.init();
///
/// // 3. Use typed collections
/// final users = store.collection<User>(
///   'users',
///   fromJson: User.fromJson,
///   toJson: (u) => u.toJson(),
///   getId: (u) => u.id,
/// );
///
/// // 4. CRUD operations work offline
/// users.insert(User(id: '1', name: 'Alice'));
/// users.update(User(id: '1', name: 'Alice Smith'));
/// users.delete('1');
///
/// // 5. Sync when online
/// final result = await store.sync();
/// ```
library;

// Core API
export 'src/core/clock.dart';
export 'src/core/collection.dart';
export 'src/core/hooks.dart';
export 'src/core/operation.dart';
export 'src/core/record.dart';
export 'src/core/schema.dart';
export 'src/core/sync_store.dart';

// Persistence
export 'src/persistence/file_adapter.dart';
export 'src/persistence/persistence_adapter.dart';

// Transport
export 'src/transport/http_transport.dart';
export 'src/transport/transport.dart';
export 'src/transport/websocket_transport.dart';

// Debug (for DevTools extension)
export 'src/debug/debug_service.dart';

// FFI (advanced usage)
export 'src/ffi/native_store.dart'
    show NativeStore, NativeStoreException, MergeStrategy;
