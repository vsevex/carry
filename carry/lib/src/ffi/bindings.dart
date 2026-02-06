import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'library_loader.dart';

// ============================================================================
// Native Function Types (C signatures)
// ============================================================================

// Store lifecycle
typedef CarryStoreNewNative = Pointer<Void> Function(
  Pointer<Utf8> schemaJson,
  Pointer<Utf8> nodeId,
);
typedef CarryStoreFreeNative = Void Function(Pointer<Void> store);
typedef CarryStringFreeNative = Void Function(Pointer<Utf8> s);

// Store operations
typedef CarryStoreApplyNative = Pointer<Utf8> Function(
  Pointer<Void> store,
  Pointer<Utf8> opJson,
  Int64 timestamp,
);
typedef CarryStoreGetNative = Pointer<Utf8> Function(
  Pointer<Void> store,
  Pointer<Utf8> collection,
  Pointer<Utf8> id,
);
typedef CarryStoreQueryNative = Pointer<Utf8> Function(
  Pointer<Void> store,
  Pointer<Utf8> collection,
  Int32 includeDeleted,
);
typedef CarryStorePendingCountNative = Int64 Function(Pointer<Void> store);
typedef CarryStorePendingOpsNative = Pointer<Utf8> Function(
  Pointer<Void> store,
);
typedef CarryStoreAcknowledgeNative = Pointer<Utf8> Function(
  Pointer<Void> store,
  Pointer<Utf8> opIdsJson,
);
typedef CarryStoreTickNative = Pointer<Utf8> Function(Pointer<Void> store);

// Reconciliation
typedef CarryStoreReconcileNative = Pointer<Utf8> Function(
  Pointer<Void> store,
  Pointer<Utf8> remoteOpsJson,
  Int32 strategy,
);

// Snapshots
typedef CarryStoreExportNative = Pointer<Utf8> Function(Pointer<Void> store);
typedef CarryStoreImportNative = Pointer<Utf8> Function(
  Pointer<Void> store,
  Pointer<Utf8> snapshotJson,
);
typedef CarryStoreMetadataNative = Pointer<Utf8> Function(Pointer<Void> store);

// Utilities
typedef CarryVersionNative = Pointer<Utf8> Function();
typedef CarrySnapshotFormatVersionNative = Int32 Function();

// ============================================================================
// Dart Function Types
// ============================================================================

typedef CarryStoreNew = Pointer<Void> Function(
  Pointer<Utf8> schemaJson,
  Pointer<Utf8> nodeId,
);
typedef CarryStoreFree = void Function(Pointer<Void> store);
typedef CarryStringFree = void Function(Pointer<Utf8> s);

typedef CarryStoreApply = Pointer<Utf8> Function(
  Pointer<Void> store,
  Pointer<Utf8> opJson,
  int timestamp,
);
typedef CarryStoreGet = Pointer<Utf8> Function(
  Pointer<Void> store,
  Pointer<Utf8> collection,
  Pointer<Utf8> id,
);
typedef CarryStoreQuery = Pointer<Utf8> Function(
  Pointer<Void> store,
  Pointer<Utf8> collection,
  int includeDeleted,
);
typedef CarryStorePendingCount = int Function(Pointer<Void> store);
typedef CarryStorePendingOps = Pointer<Utf8> Function(Pointer<Void> store);
typedef CarryStoreAcknowledge = Pointer<Utf8> Function(
  Pointer<Void> store,
  Pointer<Utf8> opIdsJson,
);
typedef CarryStoreTick = Pointer<Utf8> Function(Pointer<Void> store);

typedef CarryStoreReconcile = Pointer<Utf8> Function(
  Pointer<Void> store,
  Pointer<Utf8> remoteOpsJson,
  int strategy,
);

typedef CarryStoreExport = Pointer<Utf8> Function(Pointer<Void> store);
typedef CarryStoreImport = Pointer<Utf8> Function(
  Pointer<Void> store,
  Pointer<Utf8> snapshotJson,
);
typedef CarryStoreMetadata = Pointer<Utf8> Function(Pointer<Void> store);

typedef CarryVersion = Pointer<Utf8> Function();
typedef CarrySnapshotFormatVersion = int Function();

// ============================================================================
// Bindings Class
// ============================================================================

/// FFI bindings to the Carry Rust engine.
class CarryBindings {
  CarryBindings._();

  static final CarryBindings instance = CarryBindings._();

  final DynamicLibrary _lib = carryLibrary;

  // Store lifecycle
  late final carryStoreNew = _lib
      .lookup<NativeFunction<CarryStoreNewNative>>('carry_store_new')
      .asFunction<CarryStoreNew>();

  late final carryStoreFree = _lib
      .lookup<NativeFunction<CarryStoreFreeNative>>('carry_store_free')
      .asFunction<CarryStoreFree>();

  late final carryStringFree = _lib
      .lookup<NativeFunction<CarryStringFreeNative>>('carry_string_free')
      .asFunction<CarryStringFree>();

  // Store operations
  late final carryStoreApply = _lib
      .lookup<NativeFunction<CarryStoreApplyNative>>('carry_store_apply')
      .asFunction<CarryStoreApply>();

  late final carryStoreGet = _lib
      .lookup<NativeFunction<CarryStoreGetNative>>('carry_store_get')
      .asFunction<CarryStoreGet>();

  late final carryStoreQuery = _lib
      .lookup<NativeFunction<CarryStoreQueryNative>>('carry_store_query')
      .asFunction<CarryStoreQuery>();

  late final carryStorePendingCount = _lib
      .lookup<NativeFunction<CarryStorePendingCountNative>>(
        'carry_store_pending_count',
      )
      .asFunction<CarryStorePendingCount>();

  late final carryStorePendingOps = _lib
      .lookup<NativeFunction<CarryStorePendingOpsNative>>(
        'carry_store_pending_ops',
      )
      .asFunction<CarryStorePendingOps>();

  late final carryStoreAcknowledge = _lib
      .lookup<NativeFunction<CarryStoreAcknowledgeNative>>(
        'carry_store_acknowledge',
      )
      .asFunction<CarryStoreAcknowledge>();

  late final carryStoreTick = _lib
      .lookup<NativeFunction<CarryStoreTickNative>>('carry_store_tick')
      .asFunction<CarryStoreTick>();

  // Reconciliation
  late final carryStoreReconcile = _lib
      .lookup<NativeFunction<CarryStoreReconcileNative>>(
        'carry_store_reconcile',
      )
      .asFunction<CarryStoreReconcile>();

  // Snapshots
  late final carryStoreExport = _lib
      .lookup<NativeFunction<CarryStoreExportNative>>('carry_store_export')
      .asFunction<CarryStoreExport>();

  late final carryStoreImport = _lib
      .lookup<NativeFunction<CarryStoreImportNative>>('carry_store_import')
      .asFunction<CarryStoreImport>();

  late final carryStoreMetadata = _lib
      .lookup<NativeFunction<CarryStoreMetadataNative>>('carry_store_metadata')
      .asFunction<CarryStoreMetadata>();

  // Utilities
  late final carryVersion = _lib
      .lookup<NativeFunction<CarryVersionNative>>('carry_version')
      .asFunction<CarryVersion>();

  late final carrySnapshotFormatVersion = _lib
      .lookup<NativeFunction<CarrySnapshotFormatVersionNative>>(
        'carry_snapshot_format_version',
      )
      .asFunction<CarrySnapshotFormatVersion>();
}
