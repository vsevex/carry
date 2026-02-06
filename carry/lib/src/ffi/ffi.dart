/// FFI layer for Carry engine integration.
///
/// This library provides low-level bindings to the Rust engine.
/// Most users should use the higher-level [SyncStore] API instead.
library;

export 'bindings.dart' show CarryBindings;
export 'library_loader.dart' show loadCarryLibrary, carryLibrary;
export 'native_store.dart'
    show NativeStore, NativeStoreException, MergeStrategy;
