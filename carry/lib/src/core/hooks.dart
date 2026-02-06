import 'operation.dart';
import 'record.dart';

/// Context passed to operation hooks.
class OperationContext<T> {
  OperationContext({
    required this.collection,
    required this.recordId,
    required this.timestamp,
    this.item,
    this.existingRecord,
  });

  /// The collection name.
  final String collection;

  /// The record ID.
  final String recordId;

  /// The item being operated on (for insert/update).
  final T? item;

  /// The existing record (for update/delete).
  final Record? existingRecord;

  /// Timestamp of the operation.
  final int timestamp;
}

/// Context passed to sync hooks.
class SyncContext {
  SyncContext({
    required this.pendingOps,
    this.pulledOps,
    this.conflicts,
  });

  /// Operations to be pushed.
  final List<Operation> pendingOps;

  /// Operations received from server (after pull).
  final List<Operation>? pulledOps;

  /// Conflicts that occurred during reconciliation.
  final List<Conflict>? conflicts;
}

/// Hooks for intercepting store operations.
///
/// All hooks are optional. Return values from "before" hooks can cancel
/// or modify operations.
///
/// ```dart
/// final store = SyncStore(
///   schema: schema,
///   nodeId: nodeId,
///   hooks: StoreHooks(
///     beforeInsert: (ctx) {
///       print('Inserting ${ctx.recordId} into ${ctx.collection}');
///       return true; // Allow the operation
///     },
///     afterSync: (ctx) {
///       print('Synced ${ctx.pulledOps?.length ?? 0} operations');
///     },
///   ),
/// );
/// ```
class StoreHooks {
  const StoreHooks({
    this.beforeInsert,
    this.afterInsert,
    this.beforeUpdate,
    this.afterUpdate,
    this.beforeDelete,
    this.afterDelete,
    this.beforeSync,
    this.afterSync,
    this.onSyncError,
    this.onConflict,
  });

  /// Called before inserting a record.
  /// Return `false` to cancel the operation.
  final bool Function(OperationContext context)? beforeInsert;

  /// Called after a record is inserted.
  final void Function(OperationContext context, Record record)? afterInsert;

  /// Called before updating a record.
  /// Return `false` to cancel the operation.
  final bool Function(OperationContext context)? beforeUpdate;

  /// Called after a record is updated.
  final void Function(OperationContext context, Record record)? afterUpdate;

  /// Called before deleting a record.
  /// Return `false` to cancel the operation.
  final bool Function(OperationContext context)? beforeDelete;

  /// Called after a record is deleted.
  final void Function(OperationContext context)? afterDelete;

  /// Called before starting a sync.
  /// Return `false` to cancel the sync.
  final bool Function(SyncContext context)? beforeSync;

  /// Called after sync completes successfully.
  final void Function(SyncContext context)? afterSync;

  /// Called when a sync error occurs.
  final void Function(Object error, SyncContext context)? onSyncError;

  /// Called when a conflict is detected during reconciliation.
  final void Function(Conflict conflict)? onConflict;

  /// Empty hooks (no-op).
  static const StoreHooks none = StoreHooks();

  /// Combine multiple hooks. Later hooks take precedence.
  StoreHooks merge(StoreHooks other) => StoreHooks(
        beforeInsert: other.beforeInsert ?? beforeInsert,
        afterInsert: other.afterInsert ?? afterInsert,
        beforeUpdate: other.beforeUpdate ?? beforeUpdate,
        afterUpdate: other.afterUpdate ?? afterUpdate,
        beforeDelete: other.beforeDelete ?? beforeDelete,
        afterDelete: other.afterDelete ?? afterDelete,
        beforeSync: other.beforeSync ?? beforeSync,
        afterSync: other.afterSync ?? afterSync,
        onSyncError: other.onSyncError ?? onSyncError,
        onConflict: other.onConflict ?? onConflict,
      );
}

/// Exception thrown when an operation is cancelled by a hook.
class OperationCancelledException implements Exception {
  OperationCancelledException({
    required this.operation,
    required this.collection,
    required this.recordId,
  });
  final String operation;
  final String collection;
  final String recordId;

  @override
  String toString() =>
      'OperationCancelledException: $operation on $collection/$recordId was cancelled by hook';
}
