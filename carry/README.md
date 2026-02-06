# Carry

A local-first data cache and sync layer for Flutter apps, powered by a deterministic Rust core.

## Features

- **Offline-first**: Your app works without network connectivity
- **Fast**: Local operations are instant, sync happens in the background
- **Deterministic**: Same inputs always produce the same outputs
- **Conflict resolution**: Built-in strategies for handling concurrent edits
- **Type-safe**: Full Dart type support with your own model classes

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  carry: ^0.1.0
```

## Quick Start

### 1. Define your schema

```dart
import 'package:carry/carry.dart';

final schema = Schema.v(1)
  .collection('users', [
    Field.string('name', required: true),
    Field.string('email'),
    Field.int_('age'),
  ])
  .collection('posts', [
    Field.string('title', required: true),
    Field.string('body'),
    Field.timestamp('createdAt'),
  ])
  .build();
```

### 2. Create your model classes

```dart
class User {
  final String id;
  final String name;
  final String? email;
  final int? age;

  User({required this.id, required this.name, this.email, this.age});

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String?,
    age: json['age'] as int?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (email != null) 'email': email,
    if (age != null) 'age': age,
  };
}
```

### 3. Initialize the store

```dart
final store = SyncStore(
  schema: schema,
  nodeId: 'device_${uuid.v4()}',
  persistence: await FilePersistenceAdapter.create(
    baseDirectory: await getApplicationDocumentsDirectory(),
  ),
  transport: HttpTransport(
    baseUrl: 'https://api.example.com',
    headers: {'Authorization': 'Bearer $token'},
  ),
);

await store.init();
```

### 4. Use typed collections

```dart
final users = store.collection<User>(
  'users',
  fromJson: User.fromJson,
  toJson: (u) => u.toJson(),
  getId: (u) => u.id,
);

// Insert
users.insert(User(id: '1', name: 'Alice', email: 'alice@example.com'));

// Update
users.update(User(id: '1', name: 'Alice Smith', email: 'alice@example.com'));

// Delete
users.delete('1');

// Query
final alice = users.get('1');
final allUsers = users.all();
final adults = users.where((u) => (u.age ?? 0) >= 18);
```

### 5. Sync when online

```dart
final result = await store.sync();
print('Pushed: ${result.pushedCount}, Pulled: ${result.pulledCount}');
if (result.conflicts.isNotEmpty) {
  print('Resolved ${result.conflicts.length} conflicts');
}
```

### 6. Watch for changes

```dart
users.watch().listen((userList) {
  setState(() => _users = userList);
});
```

## Persistence

The `PersistenceAdapter` interface defines how Carry stores data locally. The included `FilePersistenceAdapter` stores data as JSON files.

Implement the `PersistenceAdapter` interface for custom storage:

```dart
class MyPersistenceAdapter implements PersistenceAdapter {
  @override
  Future<String?> read(String key) async {
    // Read from your storage
  }

  @override
  Future<void> write(String key, String value) async {
    // Write to your storage
  }

  @override
  Future<void> delete(String key) async {
    // Delete from your storage
  }

  @override
  Future<void> clear() async {
    // Clear all stored data
  }
}
```

## Transport

The `Transport` interface defines how Carry communicates with your backend. The included `HttpTransport` implements a simple sync protocol:

- `GET /sync?since={token}` - Pull operations
- `POST /sync` - Push operations

Implement the `Transport` interface for custom backends:

```dart
class MyTransport implements Transport {
  @override
  Future<PullResult> pull(String? lastSyncToken) async {
    // Fetch operations from your backend
  }

  @override
  Future<PushResult> push(List<Operation> operations) async {
    // Send operations to your backend
  }
}
```

## Conflict Resolution

Carry uses deterministic conflict resolution. When the same record is modified on multiple devices, the merge strategy determines the winner:

- `MergeStrategy.clockWins` (default): Higher logical clock wins
- `MergeStrategy.timestampWins`: Higher timestamp wins

```dart
final store = SyncStore(
  schema: schema,
  nodeId: nodeId,
  mergeStrategy: MergeStrategy.timestampWins,
);
```

## Hooks

Hooks allow you to intercept operations and sync events. All hooks are optional.

```dart
final store = SyncStore(
  schema: schema,
  nodeId: nodeId,
  hooks: StoreHooks(
    // Operation hooks - return false to cancel
    beforeInsert: (ctx) {
      print('Inserting ${ctx.recordId} into ${ctx.collection}');
      return true; // Allow the operation
    },
    afterInsert: (ctx, record) {
      print('Inserted record version ${record.version}');
    },
    beforeUpdate: (ctx) => true,
    afterUpdate: (ctx, record) {},
    beforeDelete: (ctx) => true,
    afterDelete: (ctx) {},

    // Sync hooks
    beforeSync: (ctx) {
      print('Starting sync with ${ctx.pendingOps.length} pending ops');
      return true; // Allow the sync
    },
    afterSync: (ctx) {
      print('Synced ${ctx.pulledOps?.length ?? 0} operations');
    },
    onSyncError: (error, ctx) {
      print('Sync failed: $error');
    },

    // Conflict hook
    onConflict: (conflict) {
      print('Conflict on ${conflict.recordId}: ${conflict.resolution}');
    },
  ),
);
```

### Available Hooks

| Hook           | When Called                       | Return Value                  |
| -------------- | --------------------------------- | ----------------------------- |
| `beforeInsert` | Before inserting a record         | `false` cancels the operation |
| `afterInsert`  | After a record is inserted        | -                             |
| `beforeUpdate` | Before updating a record          | `false` cancels the operation |
| `afterUpdate`  | After a record is updated         | -                             |
| `beforeDelete` | Before deleting a record          | `false` cancels the operation |
| `afterDelete`  | After a record is deleted         | -                             |
| `beforeSync`   | Before starting a sync            | `false` cancels the sync      |
| `afterSync`    | After sync completes successfully | -                             |
| `onSyncError`  | When a sync error occurs          | -                             |
| `onConflict`   | When a conflict is detected       | -                             |

## Native Library

Carry requires the native Rust library (`libcarry_engine`) to be available at runtime.

### Desktop (macOS / Linux / Windows)

```bash
cd engine
cargo build --release
```

Output locations:

- macOS: `target/release/libcarry_engine.dylib`
- Linux: `target/release/libcarry_engine.so`
- Windows: `target/release/carry_engine.dll`

### iOS

Build the XCFramework with the provided script:

```bash
cd engine
./build-ios.sh
```

This creates `target/ios/CarryEngine.xcframework` with:

- `ios-arm64` - Device (arm64)
- `ios-arm64_x86_64-simulator` - Simulator (arm64 + x86_64)

### Android

Requires Android NDK. Build for all ABIs:

```bash
cd engine
./build-android.sh
```

This creates `target/android/jniLibs/` with:

- `arm64-v8a/libcarry_engine.so`
- `armeabi-v7a/libcarry_engine.so`
- `x86_64/libcarry_engine.so`
- `x86/libcarry_engine.so`

See the [example app](example/) for integration details.

## License

MIT
