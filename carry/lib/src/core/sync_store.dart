import 'dart:convert';

import 'clock.dart';
import 'collection.dart';
import 'hooks.dart';
import 'operation.dart';
import 'schema.dart';
import '../ffi/native_store.dart';
import '../persistence/persistence_adapter.dart';
import '../transport/transport.dart';

/// Result of a sync operation.
class SyncResult {
  SyncResult({
    required this.pushedCount,
    required this.pulledCount,
    required this.conflicts,
    required this.success,
    this.error,
  });

  factory SyncResult.failed(String error) => SyncResult(
        pushedCount: 0,
        pulledCount: 0,
        conflicts: [],
        success: false,
        error: error,
      );

  /// Operations that were pushed to the server.
  final int pushedCount;

  /// Operations that were pulled from the server.
  final int pulledCount;

  /// Conflicts that were resolved.
  final List<Conflict> conflicts;

  /// Whether the sync was successful.
  final bool success;

  /// Error message if sync failed.
  final String? error;
}

/// Main entry point for the Carry SDK.
///
/// A SyncStore manages local data with offline-first capabilities and
/// optional server synchronization.
///
/// ```dart
/// final schema = Schema.v(1)
///   .collection('users', [
///     Field.string('name', required: true),
///     Field.string('email'),
///   ])
///   .build();
///
/// final store = SyncStore(
///   schema: schema,
///   nodeId: 'device_1',
///   persistence: FilePersistenceAdapter(directory),
///   transport: HttpTransport(baseUrl: 'https://api.example.com'),
///   hooks: StoreHooks(
///     beforeInsert: (ctx) {
///       print('Inserting into ${ctx.collection}');
///       return true;
///     },
///   ),
/// );
///
/// await store.init();
///
/// final users = store.collection<User>(
///   'users',
///   fromJson: User.fromJson,
///   toJson: (u) => u.toJson(),
///   getId: (u) => u.id,
/// );
/// ```
class SyncStore {
  SyncStore({
    required this.schema,
    required this.nodeId,
    this.persistence,
    this.transport,
    this.mergeStrategy = MergeStrategy.clockWins,
    this.hooks = StoreHooks.none,
  });

  /// The schema defining collections and fields.
  final Schema schema;

  /// Unique identifier for this node/device.
  final String nodeId;

  /// Persistence adapter for local storage.
  final PersistenceAdapter? persistence;

  /// Transport for server communication.
  final Transport? transport;

  /// Merge strategy for conflict resolution.
  final MergeStrategy mergeStrategy;

  /// Hooks for intercepting operations and sync events.
  final StoreHooks hooks;

  NativeStore? _native;
  final Map<String, Collection<dynamic>> _collections = {};
  bool _initialized = false;
  String? _lastSyncToken;

  static const _snapshotKey = 'carry_snapshot';
  static const _syncTokenKey = 'carry_sync_token';

  /// Whether the store has been initialized.
  bool get isInitialized => _initialized;

  /// Whether a transport is configured.
  bool get hasTransport => transport != null;

  /// Initialize the store.
  ///
  /// This loads any persisted state and prepares the native engine.
  /// Must be called before using the store.
  Future<void> init() async {
    if (_initialized) {
      return;
    }

    // Create native store
    final schemaJson = jsonEncode(schema.toJson());
    _native = NativeStore.create(schemaJson, nodeId);

    // Load persisted state if available
    if (persistence != null) {
      final snapshotJson = await persistence!.read(_snapshotKey);
      if (snapshotJson != null) {
        try {
          final snapshot = jsonDecode(snapshotJson) as Map<String, dynamic>;
          _native!.import(snapshot);
        } catch (e) {
          // Ignore corrupt snapshots, start fresh
        }
      }

      _lastSyncToken = await persistence!.read(_syncTokenKey);
    }

    _initialized = true;
  }

  /// Get or create a typed collection.
  ///
  /// The type parameter [T] is your model type. You must provide:
  /// - [fromJson]: Converts JSON payload to your model
  /// - [toJson]: Converts your model to JSON payload
  /// - [getId]: Extracts the ID from your model
  Collection<T> collection<T>(
    String name, {
    required T Function(Map<String, dynamic>) fromJson,
    required Map<String, dynamic> Function(T) toJson,
    required String Function(T) getId,
  }) {
    _checkInitialized();

    if (!schema.hasCollection(name)) {
      throw ArgumentError('Collection "$name" not found in schema');
    }

    return _collections.putIfAbsent(
      name,
      () => Collection<T>(
        name: name,
        store: _native!,
        nodeId: nodeId,
        fromJson: fromJson,
        toJson: toJson,
        getId: getId,
        hooks: hooks,
      ),
    ) as Collection<T>;
  }

  /// Get pending operations count.
  int get pendingCount {
    _checkInitialized();
    return _native!.pendingCount;
  }

  /// Get pending operations.
  List<Operation> get pendingOps {
    _checkInitialized();
    // FFI returns PendingOp which has { operation: Operation, appliedAt: int }
    return _native!.pendingOps
        .map(
          (pendingOp) => Operation.fromJson(
            pendingOp['operation'] as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  /// Export the current store state as a snapshot.
  Map<String, dynamic> exportSnapshot() {
    _checkInitialized();
    return _native!.export();
  }

  /// Get the current logical clock.
  LogicalClock get clock {
    _checkInitialized();
    final clockJson = _native!.tick();
    return LogicalClock.fromJson(clockJson);
  }

  /// Synchronize with the server.
  ///
  /// This performs a pull-reconcile-push cycle:
  /// 1. Pull remote operations since last sync
  /// 2. Reconcile with local state
  /// 3. Push pending local operations
  ///
  /// Returns a [SyncResult] with details about the sync.
  Future<SyncResult> sync() async {
    _checkInitialized();

    if (transport == null) {
      return SyncResult.failed('No transport configured');
    }

    final pendingOpsList = pendingOps;
    final syncContext = SyncContext(pendingOps: pendingOpsList);

    // Call beforeSync hook
    if (hooks.beforeSync != null) {
      if (!hooks.beforeSync!(syncContext)) {
        return SyncResult.failed('Sync cancelled by beforeSync hook');
      }
    }

    try {
      // 1. Pull remote operations
      final pullResult = await transport!.pull(_lastSyncToken);
      final remoteOps = pullResult.operations.map((op) => op.toJson()).toList();

      // 2. Reconcile
      final reconcileResult = _native!.reconcile(remoteOps, mergeStrategy);
      final result = ReconcileResult.fromJson(reconcileResult);

      // Call onConflict hook for each conflict
      if (hooks.onConflict != null) {
        for (final conflict in result.conflicts) {
          hooks.onConflict!(conflict);
        }
      }

      // 3. Push pending operations
      // Use the pendingOpsList captured BEFORE reconciliation, since reconcile
      // may clear local ops from the pending queue even though they haven't
      // been pushed to the server yet.

      int pushedCount = 0;
      if (pendingOpsList.isNotEmpty) {
        final pushResult = await transport!.push(pendingOpsList);
        if (pushResult.success) {
          // Acknowledge synced operations
          _native!.acknowledge(pushResult.acknowledgedIds);
          pushedCount = pushResult.acknowledgedIds.length;
        }
      }

      // Update sync token
      if (pullResult.syncToken != null) {
        _lastSyncToken = pullResult.syncToken;
        await persistence?.write(_syncTokenKey, _lastSyncToken!);
      }

      // Persist state
      await _persistState();

      // Notify collections of changes
      _notifyCollections();

      final syncResult = SyncResult(
        pushedCount: pushedCount,
        pulledCount: pullResult.operations.length,
        conflicts: result.conflicts,
        success: true,
      );

      // Call afterSync hook
      if (hooks.afterSync != null) {
        final afterContext = SyncContext(
          pendingOps: pendingOpsList,
          pulledOps: pullResult.operations,
          conflicts: result.conflicts,
        );
        hooks.afterSync!(afterContext);
      }

      return syncResult;
    } catch (e) {
      // Call onSyncError hook
      if (hooks.onSyncError != null) {
        hooks.onSyncError!(e, syncContext);
      }
      return SyncResult.failed(e.toString());
    }
  }

  /// Save the current state to persistence.
  Future<void> save() async {
    _checkInitialized();
    await _persistState();
  }

  /// Close the store and release resources.
  ///
  /// After calling this, the store cannot be used.
  Future<void> close() async {
    if (!_initialized) {
      return;
    }

    // Persist final state
    await _persistState();

    // Dispose collections
    for (final collection in _collections.values) {
      collection.dispose();
    }
    _collections.clear();

    // Dispose native store
    _native?.dispose();
    _native = null;
    _initialized = false;
  }

  void _checkInitialized() {
    if (!_initialized) {
      throw StateError('SyncStore not initialized. Call init() first.');
    }
  }

  Future<void> _persistState() async {
    if (persistence == null || _native == null) {
      return;
    }

    final snapshot = _native!.export();
    final snapshotJson = jsonEncode(snapshot);
    await persistence!.write(_snapshotKey, snapshotJson);
  }

  void _notifyCollections() {
    for (final collection in _collections.values) {
      // Notify watchers of changes from sync
      collection.notifyListeners();
    }
  }

  /// Get the engine version string.
  static String get engineVersion => NativeStore.engineVersion;

  /// Get the snapshot format version.
  static int get snapshotFormatVersion => NativeStore.snapshotFormatVersion;
}
