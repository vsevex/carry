# Carry Todo Example

A local-first todo app demonstrating the Carry SDK.

## Features

- Create, update, delete todos
- Mark todos as complete
- Data persists locally (offline-first)
- Reactive UI updates via `watch()`
- Hooks for logging operations

## Building the Native Engine

Before running the example, build the native Carry engine for your target platform.

### macOS / Linux / Windows (Desktop)

```bash
cd engine
cargo build --release
```

Output:

- macOS: `engine/target/release/libcarry_engine.dylib`
- Linux: `engine/target/release/libcarry_engine.so`
- Windows: `engine/target/release/carry_engine.dll`

### iOS

Build the XCFramework:

```bash
cd engine
./build-ios.sh
```

This creates `engine/target/ios/CarryEngine.xcframework`.

The example project is already configured via xcconfig files to link the library.

### Android

Requires Android NDK. Install via Android Studio SDK Manager or:

```bash
sdkmanager --install "ndk;26.1.10909125"
```

Build the native libraries:

```bash
cd engine
./build-android.sh
```

This creates `engine/target/android/jniLibs/` with libraries for all ABIs:

- `arm64-v8a/libcarry_engine.so`
- `armeabi-v7a/libcarry_engine.so`
- `x86_64/libcarry_engine.so`
- `x86/libcarry_engine.so`

The example project's `build.gradle.kts` is already configured to include these.

## Running the Example

### macOS

```bash
cd carry/example
flutter pub get
export DYLD_LIBRARY_PATH=$PWD/../../engine/target/release:$DYLD_LIBRARY_PATH
flutter run -d macos
```

### iOS Simulator

```bash
cd carry/example
flutter pub get
cd ios && pod install && cd ..
flutter run -d ios
```

### iOS Device

Requires code signing. Open `ios/Runner.xcworkspace` in Xcode to configure signing, then:

```bash
flutter run -d <device-id>
```

### Android Emulator / Device

```bash
cd carry/example
flutter pub get
flutter run -d android
```

### Linux

```bash
cd carry/example
flutter pub get
export LD_LIBRARY_PATH=$PWD/../../engine/target/release:$LD_LIBRARY_PATH
flutter run -d linux
```

## Code Highlights

### Schema Definition

```dart
final schema = Schema.v(1)
    .collection('todos', [
      Field.string('id', required: true),
      Field.string('title', required: true),
      Field.bool_('completed'),
      Field.int_('createdAt'),
    ])
    .build();
```

### Store Initialization

```dart
_store = SyncStore(
  schema: schema,
  nodeId: 'device_${uuid.v4()}',
  persistence: FilePersistenceAdapter(directory: dataDir),
  hooks: StoreHooks(
    afterInsert: (ctx, record) => print('Created: ${ctx.recordId}'),
  ),
);

await _store.init();
```

### Typed Collection

```dart
_todos = _store.collection<Todo>(
  'todos',
  fromJson: Todo.fromJson,
  toJson: (t) => t.toJson(),
  getId: (t) => t.id,
);
```

### CRUD Operations

```dart
// Create
_todos.insert(Todo(id: uuid.v4(), title: 'Buy milk'));

// Read
final todo = _todos.get('some-id');
final all = _todos.all();

// Update
_todos.update(todo.copyWith(completed: true));

// Delete
_todos.delete('some-id');
```

### Reactive UI

```dart
_todos.watch().listen((todos) {
  setState(() => _todoList = todos);
});
```

## Troubleshooting

### "Could not load libcarry_engine" error

Make sure you've built the native library for your platform:

- **Desktop**: Set library path environment variable
- **iOS**: Run `./build-ios.sh`
- **Android**: Run `./build-android.sh`

### iOS: "symbol not found" error

The static library symbols are being stripped. Ensure:

1. You've run `./build-ios.sh` in the engine directory
2. The xcconfig files include `-force_load` for the library
3. Run `pod install` after any changes

If issues persist, open `ios/Runner.xcworkspace` in Xcode and add to Build Settings > Other Linker Flags:

```bash
-force_load $(SRCROOT)/../../../engine/target/ios/CarryEngine.xcframework/ios-arm64/libcarry_engine.a
```

For simulator:

```bash
-force_load $(SRCROOT)/../../../engine/target/ios/CarryEngine.xcframework/ios-arm64_x86_64-simulator/libcarry_engine.a
```

### Android: "library not found" error

Ensure:

1. You've run `./build-android.sh` in the engine directory
2. The jniLibs are in the correct location
3. Your device's ABI is supported (check with `adb shell getprop ro.product.cpu.abi`)

You can also copy the libraries manually:

```bash
cp -r engine/target/android/jniLibs carry/example/android/app/src/main/
```
