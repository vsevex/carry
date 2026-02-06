import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'clock.dart';
import 'collection.dart';
import 'hooks.dart';
import 'operation.dart';
import 'schema.dart';
import '../debug/debug_service.dart';
import '../debug/logger.dart';
import '../ffi/native_store.dart';
import '../persistence/persistence_adapter.dart';
import '../transport/transport.dart';
import '../transport/websocket_transport.dart';

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
  StreamSubscription<List<Operation>>? _incomingOpsSubscription;
  StreamSubscription<WebSocketConnectionState>? _connectionStateSubscription;

  static const _snapshotKey = 'carry_snapshot';
  static const _syncTokenKey = 'carry_sync_token';

  /// Whether the store has been initialized.
  bool get isInitialized => _initialized;

  /// Whether a transport is configured.
  bool get hasTransport => transport != null;

  /// Whether using WebSocket transport.
  bool get hasWebSocketTransport => transport is WebSocketTransport;

  /// Get the WebSocket transport if configured.
  WebSocketTransport? get webSocketTransport =>
      transport is WebSocketTransport ? transport as WebSocketTransport : null;

  /// Initialize the store.
  ///
  /// This loads any persisted state and prepares the native engine.
  /// Must be called before using the store.
  Future<void> init() async {
    if (_initialized) {
      logStore('Store already initialized');
      return;
    }

    logStore(
      'Initializing store',
      level: CarryLogLevel.info,
      data: {
        'nodeId': nodeId,
        'schemaVersion': schema.version,
        'collections': schema.collectionNames.toList(),
        'hasPersistence': persistence != null,
        'hasTransport': transport != null,
        'transportType': transport?.runtimeType.toString(),
      },
    );

    // Create native store
    final schemaJson = jsonEncode(schema.toJson());
    _native = NativeStore.create(schemaJson, nodeId);
    logStore('Native store created');

    // Load persisted state if available
    if (persistence != null) {
      final snapshotJson = await persistence!.read(_snapshotKey);
      if (snapshotJson != null) {
        try {
          final snapshot = jsonDecode(snapshotJson) as Map<String, dynamic>;
          _native!.import(snapshot);
          logStore(
            'Loaded persisted state',
            level: CarryLogLevel.info,
            data: {'snapshotSize': snapshotJson.length},
          );
        } catch (e) {
          logStore(
            'Failed to load persisted state, starting fresh',
            level: CarryLogLevel.warning,
            error: e,
          );
        }
      }

      _lastSyncToken = await persistence!.read(_syncTokenKey);
      if (_lastSyncToken != null) {
        logStore(
          'Loaded sync token',
          data: {'token': _lastSyncToken},
        );
      }
    }

    _initialized = true;

    // Set up WebSocket transport if configured
    if (transport is WebSocketTransport) {
      _setupWebSocketTransport(transport as WebSocketTransport);
    }

    // Register debug service in debug mode
    if (kDebugMode) {
      CarryDebugService.instance.register(this);
    }

    logStore('Store initialized successfully', level: CarryLogLevel.info);
  }

  void _setupWebSocketTransport(WebSocketTransport wsTransport) {
    logStore('Setting up WebSocket transport');

    // Subscribe to incoming operations
    _incomingOpsSubscription = wsTransport.incomingOperations.listen(
      _handleIncomingOperations,
      onError: (error) {
        logStore(
          'WebSocket incoming ops error',
          level: CarryLogLevel.error,
          error: error,
        );
      },
    );

    // Optionally track connection state for UI updates
    _connectionStateSubscription = wsTransport.connectionState.listen(
      (state) {
        logStore(
          'WebSocket connection state changed',
          data: {'state': state.name},
        );
      },
    );
  }

  /// Handle incoming operations pushed from the server via WebSocket.
  ///
  /// This reconciles the incoming operations with local state and notifies
  /// all collection listeners of changes.
  Future<void> _handleIncomingOperations(List<Operation> operations) async {
    if (operations.isEmpty || _native == null) {
      return;
    }

    logSync(
      'Processing incoming operations',
      level: CarryLogLevel.info,
      data: {
        'count': operations.length,
        'opIds': operations.map((op) => op.opId).toList(),
      },
    );

    try {
      // Convert to JSON for reconciliation
      final remoteOps = operations.map((op) => op.toJson()).toList();

      // Reconcile with local state
      final reconcileResult = _native!.reconcile(remoteOps, mergeStrategy);
      final result = ReconcileResult.fromJson(reconcileResult);

      logSync(
        'Reconciliation completed',
        data: {
          'appliedRemote': result.acceptedRemote.length,
          'conflicts': result.conflicts.length,
        },
      );

      // Log and handle conflicts
      for (final conflict in result.conflicts) {
        logConflict(
          'Conflict resolved',
          data: {
            'recordId': conflict.recordId,
            'collection': conflict.collection,
            'localOpId': conflict.localOpId,
            'remoteOpId': conflict.remoteOpId,
            'winner': conflict.winnerId,
            'resolution': conflict.resolution,
          },
        );
        hooks.onConflict?.call(conflict);
      }

      // Persist state
      await _persistState();

      // Notify collections of changes
      _notifyCollections();

      logSync(
        'Incoming operations processed',
        level: CarryLogLevel.info,
        data: {'applied': result.acceptedRemote.length},
      );
    } catch (e) {
      logSync(
        'Failed to process incoming operations',
        level: CarryLogLevel.error,
        error: e,
      );
    }
  }

  /// Connect the WebSocket transport.
  ///
  /// This is only needed if using [WebSocketTransport]. Call this after [init]
  /// to establish the WebSocket connection and start receiving real-time updates.
  Future<void> connectWebSocket() async {
    _checkInitialized();
    if (transport is WebSocketTransport) {
      await (transport as WebSocketTransport).connect();
    }
  }

  /// Disconnect the WebSocket transport.
  Future<void> disconnectWebSocket() async {
    if (transport is WebSocketTransport) {
      await (transport as WebSocketTransport).disconnect();
    }
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
    return _native!.pendingOps.map((pendingOp) {
      final operation = pendingOp['operation'];
      // Handle both Map and JSON string from FFI
      final opMap = operation is String
          ? jsonDecode(operation) as Map<String, dynamic>
          : operation as Map<String, dynamic>;
      return Operation.fromJson(opMap);
    }).toList();
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
      logSync(
        'Sync failed - no transport configured',
        level: CarryLogLevel.warning,
      );
      final result = SyncResult.failed('No transport configured');
      if (kDebugMode) {
        CarryDebugService.instance.recordSync(result);
      }
      return result;
    }

    final pendingOpsList = pendingOps;
    final syncContext = SyncContext(pendingOps: pendingOpsList);
    final stopwatch = Stopwatch()..start();

    logSync(
      'Starting sync',
      level: CarryLogLevel.info,
      data: {
        'pendingOps': pendingOpsList.length,
        'lastSyncToken': _lastSyncToken,
      },
    );

    // Call beforeSync hook
    if (hooks.beforeSync != null) {
      if (!hooks.beforeSync!(syncContext)) {
        logSync('Sync cancelled by beforeSync hook', level: CarryLogLevel.info);
        final result = SyncResult.failed('Sync cancelled by beforeSync hook');
        if (kDebugMode) {
          CarryDebugService.instance
              .recordSync(result, durationMs: stopwatch.elapsedMilliseconds);
        }
        return result;
      }
    }

    try {
      // 1. Pull remote operations
      logSync('Pulling remote operations');
      final pullResult = await transport!.pull(_lastSyncToken);
      final remoteOps = pullResult.operations.map((op) => op.toJson()).toList();

      logSync(
        'Pulled operations',
        data: {
          'count': pullResult.operations.length,
          'hasMore': pullResult.hasMore,
          'newSyncToken': pullResult.syncToken,
        },
      );

      // 2. Reconcile
      logSync('Reconciling with local state');
      final reconcileResult = _native!.reconcile(remoteOps, mergeStrategy);
      final result = ReconcileResult.fromJson(reconcileResult);

      logSync(
        'Reconciliation completed',
        data: {
          'appliedRemote': result.acceptedRemote.length,
          'conflicts': result.conflicts.length,
        },
      );

      // Log and handle conflicts
      for (final conflict in result.conflicts) {
        logConflict(
          'Conflict resolved during sync',
          data: {
            'recordId': conflict.recordId,
            'collection': conflict.collection,
            'localOpId': conflict.localOpId,
            'remoteOpId': conflict.remoteOpId,
            'winner': conflict.winnerId,
            'resolution': conflict.resolution,
          },
        );
        hooks.onConflict?.call(conflict);
      }

      // 3. Push pending operations
      // Use the pendingOpsList captured BEFORE reconciliation, since reconcile
      // may clear local ops from the pending queue even though they haven't
      // been pushed to the server yet.

      int pushedCount = 0;
      if (pendingOpsList.isNotEmpty) {
        logSync(
          'Pushing pending operations',
          data: {'count': pendingOpsList.length},
        );
        final pushResult = await transport!.push(pendingOpsList);
        if (pushResult.success) {
          // Acknowledge synced operations
          _native!.acknowledge(pushResult.acknowledgedIds);
          pushedCount = pushResult.acknowledgedIds.length;
          logSync(
            'Push completed',
            data: {'acknowledged': pushedCount},
          );
        } else {
          logSync(
            'Push failed',
            level: CarryLogLevel.warning,
            data: {'error': pushResult.error},
          );
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

      stopwatch.stop();
      final syncResult = SyncResult(
        pushedCount: pushedCount,
        pulledCount: pullResult.operations.length,
        conflicts: result.conflicts,
        success: true,
      );

      logSync(
        'Sync completed successfully',
        level: CarryLogLevel.info,
        data: {
          'pushed': pushedCount,
          'pulled': pullResult.operations.length,
          'conflicts': result.conflicts.length,
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );

      // Record in debug service
      if (kDebugMode) {
        CarryDebugService.instance
            .recordSync(syncResult, durationMs: stopwatch.elapsedMilliseconds);
      }

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
      stopwatch.stop();

      logSync(
        'Sync failed',
        level: CarryLogLevel.error,
        data: {'durationMs': stopwatch.elapsedMilliseconds},
        error: e,
      );

      final failedResult = SyncResult.failed(e.toString());

      // Record in debug service
      if (kDebugMode) {
        CarryDebugService.instance.recordSync(
          failedResult,
          durationMs: stopwatch.elapsedMilliseconds,
        );
      }

      // Call onSyncError hook
      if (hooks.onSyncError != null) {
        hooks.onSyncError!(e, syncContext);
      }
      return failedResult;
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

    // Cancel WebSocket subscriptions
    await _incomingOpsSubscription?.cancel();
    _incomingOpsSubscription = null;
    await _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;

    // Close WebSocket transport
    if (transport is WebSocketTransport) {
      await (transport as WebSocketTransport).close();
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
