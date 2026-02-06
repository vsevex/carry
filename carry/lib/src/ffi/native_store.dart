import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../debug/logger.dart';
import 'bindings.dart';

/// Exception thrown when a native operation fails.
class NativeStoreException implements Exception {
  NativeStoreException(this.message);

  final String message;

  @override
  String toString() => 'NativeStoreException: $message';
}

/// Merge strategy for reconciliation.
enum MergeStrategy {
  /// Higher logical clock wins (default).
  clockWins(0),

  /// Higher timestamp wins.
  timestampWins(1);

  const MergeStrategy(this.value);

  final int value;
}

/// Low-level wrapper around the Rust store FFI.
///
/// This class handles memory management and JSON serialization for FFI calls.
/// Users should prefer the higher-level [SyncStore] API.
class NativeStore {
  /// Create a new native store with the given schema and node ID.
  ///
  /// The [schemaJson] should be a valid JSON representation of the schema.
  /// The [nodeId] uniquely identifies this node/device.
  ///
  /// Throws [NativeStoreException] if creation fails.
  factory NativeStore.create(String schemaJson, String nodeId) {
    final bindings = CarryBindings.instance;
    final schemaPtr = schemaJson.toNativeUtf8();
    final nodeIdPtr = nodeId.toNativeUtf8();

    try {
      final ptr = bindings.carryStoreNew(schemaPtr, nodeIdPtr);
      if (ptr == nullptr) {
        throw NativeStoreException(
          'Failed to create store: invalid schema or node ID',
        );
      }
      return NativeStore._(ptr);
    } finally {
      malloc
        ..free(schemaPtr)
        ..free(nodeIdPtr);
    }
  }
  NativeStore._(this._ptr) : _bindings = CarryBindings.instance;

  final Pointer<Void> _ptr;
  final CarryBindings _bindings;
  bool _disposed = false;

  void _checkDisposed() {
    if (_disposed) {
      throw StateError('NativeStore has been disposed');
    }
  }

  /// Call an FFI function that returns a JSON result string.
  /// Handles memory cleanup and error parsing.
  Map<String, dynamic> _callWithResult(
    Pointer<Utf8> Function() fn, {
    String? operation,
  }) {
    _checkDisposed();

    final stopwatch = Stopwatch()..start();
    final resultPtr = fn();
    stopwatch.stop();

    if (resultPtr == nullptr) {
      logFfi(
        'FFI call returned null',
        level: CarryLogLevel.error,
        data: {'operation': operation},
      );
      throw NativeStoreException('FFI call returned null');
    }

    try {
      final resultStr = resultPtr.toDartString();
      final result = jsonDecode(resultStr) as Map<String, dynamic>;

      if (result.containsKey('error')) {
        logFfi(
          'FFI call returned error',
          level: CarryLogLevel.error,
          data: {'operation': operation, 'error': result['error']},
        );
        throw NativeStoreException(result['error'] as String);
      }

      logFfi(
        'FFI call completed',
        level: CarryLogLevel.verbose,
        data: {
          'operation': operation,
          'durationUs': stopwatch.elapsedMicroseconds,
        },
      );

      return result;
    } finally {
      _bindings.carryStringFree(resultPtr);
    }
  }

  /// Apply an operation to the store.
  ///
  /// Returns the apply result containing the operation ID, record ID, and version.
  Map<String, dynamic> apply(Map<String, dynamic> operation, int timestamp) {
    final opType = operation['type'] ?? 'unknown';
    final collection = operation['collection'];
    final recordId = operation['record_id'];

    logFfi(
      'Applying operation',
      data: {
        'type': opType,
        'collection': collection,
        'recordId': recordId,
        'timestamp': timestamp,
      },
    );

    final opJson = jsonEncode(operation);
    final opPtr = opJson.toNativeUtf8();

    try {
      final result = _callWithResult(
        () => _bindings.carryStoreApply(_ptr, opPtr, timestamp),
        operation: 'apply',
      );
      final applyResult = result['ok'] as Map<String, dynamic>;

      logFfi(
        'Operation applied',
        data: {
          'opId': applyResult['op_id'],
          'recordId': applyResult['record_id'],
          'version': applyResult['version'],
        },
      );

      return applyResult;
    } finally {
      malloc.free(opPtr);
    }
  }

  /// Get a record by collection and ID.
  ///
  /// Returns the record as a map, or null if not found.
  Map<String, dynamic>? get(String collection, String id) {
    logFfi(
      'Getting record',
      level: CarryLogLevel.verbose,
      data: {'collection': collection, 'id': id},
    );

    final collectionPtr = collection.toNativeUtf8();
    final idPtr = id.toNativeUtf8();

    try {
      final result = _callWithResult(
        () => _bindings.carryStoreGet(_ptr, collectionPtr, idPtr),
        operation: 'get',
      );
      return result['ok'] as Map<String, dynamic>?;
    } finally {
      malloc
        ..free(collectionPtr)
        ..free(idPtr);
    }
  }

  /// Query all records in a collection.
  ///
  /// Set [includeDeleted] to true to include soft-deleted records.
  List<Map<String, dynamic>> query(
    String collection, {
    bool includeDeleted = false,
  }) {
    final collectionPtr = collection.toNativeUtf8();

    try {
      final result = _callWithResult(
        () => _bindings.carryStoreQuery(
          _ptr,
          collectionPtr,
          includeDeleted ? 1 : 0,
        ),
      );
      final list = result['ok'] as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    } finally {
      malloc.free(collectionPtr);
    }
  }

  /// Get the count of pending operations.
  int get pendingCount {
    _checkDisposed();
    return _bindings.carryStorePendingCount(_ptr);
  }

  /// Get all pending operations.
  List<Map<String, dynamic>> get pendingOps {
    final result = _callWithResult(
      () => _bindings.carryStorePendingOps(_ptr),
    );
    final list = result['ok'] as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  /// Acknowledge operations as synced by their IDs.
  void acknowledge(List<String> opIds) {
    final opIdsJson = jsonEncode(opIds);
    final opIdsPtr = opIdsJson.toNativeUtf8();

    try {
      _callWithResult(
        () => _bindings.carryStoreAcknowledge(_ptr, opIdsPtr),
      );
    } finally {
      malloc.free(opIdsPtr);
    }
  }

  /// Increment the logical clock and return the new value.
  Map<String, dynamic> tick() {
    final result = _callWithResult(
      () => _bindings.carryStoreTick(_ptr),
    );
    return result['ok'] as Map<String, dynamic>;
  }

  /// Reconcile local state with remote operations.
  ///
  /// Returns the reconciliation result containing accepted/rejected operations
  /// and any conflicts.
  Map<String, dynamic> reconcile(
    List<Map<String, dynamic>> remoteOps,
    MergeStrategy strategy,
  ) {
    logFfi(
      'Reconciling operations',
      data: {
        'remoteOpsCount': remoteOps.length,
        'strategy': strategy.name,
      },
    );

    final remoteOpsJson = jsonEncode(remoteOps);
    final remoteOpsPtr = remoteOpsJson.toNativeUtf8();

    try {
      final result = _callWithResult(
        () => _bindings.carryStoreReconcile(_ptr, remoteOpsPtr, strategy.value),
        operation: 'reconcile',
      );
      final reconcileResult = result['ok'] as Map<String, dynamic>;

      logFfi(
        'Reconciliation completed',
        data: {
          'applied': reconcileResult['applied_count'],
          'conflicts': (reconcileResult['conflicts'] as List?)?.length ?? 0,
        },
      );

      return reconcileResult;
    } finally {
      malloc.free(remoteOpsPtr);
    }
  }

  /// Export the store state as a snapshot.
  Map<String, dynamic> export() {
    final result = _callWithResult(
      () => _bindings.carryStoreExport(_ptr),
    );
    return result['ok'] as Map<String, dynamic>;
  }

  /// Import state from a snapshot.
  void import(Map<String, dynamic> snapshot) {
    final snapshotJson = jsonEncode(snapshot);
    final snapshotPtr = snapshotJson.toNativeUtf8();

    try {
      _callWithResult(
        () => _bindings.carryStoreImport(_ptr, snapshotPtr),
      );
    } finally {
      malloc.free(snapshotPtr);
    }
  }

  /// Get snapshot metadata without full export.
  Map<String, dynamic> get metadata {
    final result = _callWithResult(
      () => _bindings.carryStoreMetadata(_ptr),
    );
    return result['ok'] as Map<String, dynamic>;
  }

  /// Dispose of native resources.
  ///
  /// This MUST be called when the store is no longer needed.
  void dispose() {
    if (!_disposed) {
      _bindings.carryStoreFree(_ptr);
      _disposed = true;
    }
  }

  /// Check if this store has been disposed.
  bool get isDisposed => _disposed;

  /// Get the engine version string.
  static String get engineVersion {
    final bindings = CarryBindings.instance;
    final versionPtr = bindings.carryVersion();
    try {
      final result =
          jsonDecode(versionPtr.toDartString()) as Map<String, dynamic>;
      return result['ok'] as String;
    } finally {
      bindings.carryStringFree(versionPtr);
    }
  }

  /// Get the snapshot format version.
  static int get snapshotFormatVersion {
    final bindings = CarryBindings.instance;
    return bindings.carrySnapshotFormatVersion();
  }
}
