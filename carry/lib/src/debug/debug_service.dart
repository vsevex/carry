import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../core/operation.dart';
import '../core/sync_store.dart';
import '../transport/websocket_transport.dart';

/// Entry in sync history.
class SyncHistoryEntry {
  SyncHistoryEntry({
    required this.timestamp,
    required this.pushedCount,
    required this.pulledCount,
    required this.conflictCount,
    required this.success,
    this.error,
    this.durationMs,
  });

  final DateTime timestamp;
  final int pushedCount;
  final int pulledCount;
  final int conflictCount;
  final bool success;
  final String? error;
  final int? durationMs;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'pushedCount': pushedCount,
        'pulledCount': pulledCount,
        'conflictCount': conflictCount,
        'success': success,
        'error': error,
        'durationMs': durationMs,
      };
}

/// Entry in conflict history.
class ConflictHistoryEntry {
  ConflictHistoryEntry({
    required this.timestamp,
    required this.recordId,
    required this.collection,
    required this.localOpId,
    required this.remoteOpId,
    required this.winnerId,
    required this.resolution,
  });

  final DateTime timestamp;
  final String recordId;
  final String collection;
  final String localOpId;
  final String remoteOpId;
  final String winnerId;
  final String resolution;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'recordId': recordId,
        'collection': collection,
        'localOpId': localOpId,
        'remoteOpId': remoteOpId,
        'winnerId': winnerId,
        'resolution': resolution,
      };
}

/// Debug service for exposing Carry sync state to DevTools.
///
/// This service registers a VM service extension that can be queried
/// by the Carry DevTools extension to display sync debugging information.
///
/// Usage:
/// ```dart
/// final store = SyncStore(...);
/// await store.init();
///
/// // In debug mode, register the extension
/// if (kDebugMode) {
///   CarryDebugService.instance.register(store);
/// }
/// ```
class CarryDebugService {
  CarryDebugService._();

  static final CarryDebugService instance = CarryDebugService._();

  SyncStore? _store;
  bool _registered = false;

  /// Maximum number of sync history entries to keep.
  static const int maxSyncHistory = 50;

  /// Maximum number of conflict history entries to keep.
  static const int maxConflictHistory = 100;

  final List<SyncHistoryEntry> _syncHistory = [];
  final List<ConflictHistoryEntry> _conflictHistory = [];

  /// Sync history entries (most recent first).
  List<SyncHistoryEntry> get syncHistory => List.unmodifiable(_syncHistory);

  /// Conflict history entries (most recent first).
  List<ConflictHistoryEntry> get conflictHistory =>
      List.unmodifiable(_conflictHistory);

  /// Register the debug service with a SyncStore.
  ///
  /// This registers the VM service extension `ext.carry.getDebugInfo`.
  /// Only registers in debug mode and only once per app lifecycle.
  void register(SyncStore store) {
    if (!kDebugMode) {
      return;
    }
    if (_registered) {
      _store = store;
      return;
    }

    _store = store;
    _registerServiceExtension();
    _registered = true;
  }

  /// Record a sync result in history.
  void recordSync(SyncResult result, {int? durationMs}) {
    _syncHistory.insert(
      0,
      SyncHistoryEntry(
        timestamp: DateTime.now(),
        pushedCount: result.pushedCount,
        pulledCount: result.pulledCount,
        conflictCount: result.conflicts.length,
        success: result.success,
        error: result.error,
        durationMs: durationMs,
      ),
    );

    // Record conflicts
    for (final conflict in result.conflicts) {
      recordConflict(conflict);
    }

    // Trim history
    if (_syncHistory.length > maxSyncHistory) {
      _syncHistory.removeRange(maxSyncHistory, _syncHistory.length);
    }
  }

  /// Record a conflict in history.
  void recordConflict(Conflict conflict) {
    _conflictHistory.insert(
      0,
      ConflictHistoryEntry(
        timestamp: DateTime.now(),
        recordId: conflict.recordId,
        collection: conflict.collection,
        localOpId: conflict.localOpId,
        remoteOpId: conflict.remoteOpId,
        winnerId: conflict.winnerId,
        resolution: conflict.resolution,
      ),
    );

    // Trim history
    if (_conflictHistory.length > maxConflictHistory) {
      _conflictHistory.removeRange(maxConflictHistory, _conflictHistory.length);
    }
  }

  /// Clear all history.
  void clearHistory() {
    _syncHistory.clear();
    _conflictHistory.clear();
  }

  void _registerServiceExtension() {
    developer.registerExtension(
      'ext.carry.getDebugInfo',
      (method, parameters) async {
        try {
          final info = getDebugInfo();
          return developer.ServiceExtensionResponse.result(jsonEncode(info));
        } catch (e) {
          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.extensionError,
            e.toString(),
          );
        }
      },
    );

    // Register additional extensions for actions
    developer.registerExtension(
      'ext.carry.triggerSync',
      (method, parameters) async {
        try {
          if (_store != null) {
            final result = await _store!.sync();
            return developer.ServiceExtensionResponse.result(
              jsonEncode({
                'success': result.success,
                'pushedCount': result.pushedCount,
                'pulledCount': result.pulledCount,
                'error': result.error,
              }),
            );
          }
          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.extensionError,
            'No store registered',
          );
        } catch (e) {
          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.extensionError,
            e.toString(),
          );
        }
      },
    );

    developer.registerExtension(
      'ext.carry.clearHistory',
      (method, parameters) async {
        clearHistory();
        return developer.ServiceExtensionResponse.result(
          jsonEncode({'success': true}),
        );
      },
    );
  }

  /// Get current debug information.
  Map<String, dynamic> getDebugInfo() {
    final store = _store;
    if (store == null) {
      return {
        'error': 'No store registered',
        'registered': false,
      };
    }

    return {
      'registered': true,
      'nodeId': store.nodeId,
      'isInitialized': store.isInitialized,
      'hasTransport': store.hasTransport,
      'hasWebSocketTransport': store.hasWebSocketTransport,
      'connectionState': _getConnectionState(store),
      'pendingCount': store.isInitialized ? store.pendingCount : 0,
      'pendingOps': store.isInitialized
          ? store.pendingOps.map(_operationToJson).toList()
          : [],
      'syncHistory': _syncHistory.map((e) => e.toJson()).toList(),
      'conflictHistory': _conflictHistory.map((e) => e.toJson()).toList(),
      'collections': _getCollectionStats(store),
      'schema': _getSchemaInfo(store),
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  String _getConnectionState(SyncStore store) {
    if (!store.hasWebSocketTransport) {
      return store.hasTransport ? 'http' : 'none';
    }

    final wsTransport = store.webSocketTransport;
    if (wsTransport == null) {
      return 'unknown';
    }

    switch (wsTransport.currentState) {
      case WebSocketConnectionState.disconnected:
        return 'disconnected';
      case WebSocketConnectionState.connecting:
        return 'connecting';
      case WebSocketConnectionState.connected:
        return 'connected';
      case WebSocketConnectionState.reconnecting:
        return 'reconnecting';
    }
  }

  Map<String, dynamic> _operationToJson(Operation op) => {
        'opId': op.opId,
        'recordId': op.recordId,
        'collection': op.collection,
        'type': _getOperationType(op),
        'timestamp': op.timestamp,
      };

  String _getOperationType(Operation op) => switch (op) {
        CreateOp() => 'create',
        UpdateOp() => 'update',
        DeleteOp() => 'delete',
      };

  List<Map<String, dynamic>> _getCollectionStats(SyncStore store) {
    if (!store.isInitialized) {
      return [];
    }

    final stats = <Map<String, dynamic>>[];
    for (final collectionName in store.schema.collectionNames) {
      try {
        // Get record count from the snapshot
        final snapshot = store.exportSnapshot();
        final collections =
            snapshot['collections'] as Map<String, dynamic>? ?? {};
        final collectionData =
            collections[collectionName] as Map<String, dynamic>?;
        final records = collectionData?['records'] as Map<String, dynamic>?;

        stats.add({
          'name': collectionName,
          'recordCount': records?.length ?? 0,
        });
      } catch (_) {
        stats.add({
          'name': collectionName,
          'recordCount': 0,
        });
      }
    }
    return stats;
  }

  Map<String, dynamic> _getSchemaInfo(SyncStore store) => {
        'version': store.schema.version,
        'collections': store.schema.collectionNames.toList(),
      };
}
