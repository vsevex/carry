import 'dart:async';

import 'clock.dart';
import 'hooks.dart';
import 'operation.dart';
import 'record.dart';
import '../ffi/native_store.dart';

/// Provides a typed interface for accessing records in a collection.
///
/// Type parameter [T] is the model type. You must provide [fromJson] and
/// [toJson] functions to convert between your model and JSON.
class Collection<T> {
  Collection({
    required String name,
    required NativeStore store,
    required String nodeId,
    required T Function(Map<String, dynamic>) fromJson,
    required Map<String, dynamic> Function(T) toJson,
    required String Function(T) getId,
    StoreHooks? hooks,
  })  : _name = name,
        _store = store,
        _nodeId = nodeId,
        _fromJson = fromJson,
        _toJson = toJson,
        _getId = getId,
        _hooks = hooks ?? StoreHooks.none;

  final String _name;
  final NativeStore _store;
  final String _nodeId;
  final T Function(Map<String, dynamic>) _fromJson;
  final Map<String, dynamic> Function(T) _toJson;
  final String Function(T) _getId;
  final StoreHooks _hooks;

  final _controller = StreamController<List<T>>.broadcast();
  int _opCounter = 0;

  /// The collection name.
  String get name => _name;

  /// Insert a new item into the collection.
  ///
  /// The item must have an ID accessible via the [getId] function.
  /// Returns the inserted item.
  ///
  /// Throws [NativeStoreException] if the item already exists or validation fails.
  /// Throws [OperationCancelledException] if a beforeInsert hook returns false.
  T insert(T item) {
    final id = _getId(item);
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // Call beforeInsert hook
    if (_hooks.beforeInsert != null) {
      final ctx = OperationContext<T>(
        collection: _name,
        recordId: id,
        item: item,
        timestamp: timestamp,
      );
      if (!_hooks.beforeInsert!(ctx)) {
        throw OperationCancelledException(
          operation: 'insert',
          collection: _name,
          recordId: id,
        );
      }
    }

    final payload = _toJson(item);
    final opId = _generateOpId();

    final op = CreateOp(
      opId: opId,
      recordId: id,
      collection: _name,
      payload: payload,
      timestamp: timestamp,
      clock: _nextClock(),
    );

    _store.apply(op.toJson(), timestamp);

    // Call afterInsert hook
    if (_hooks.afterInsert != null) {
      final record = getRecord(id);
      if (record != null) {
        final ctx = OperationContext<T>(
          collection: _name,
          recordId: id,
          item: item,
          timestamp: timestamp,
        );
        _hooks.afterInsert!(ctx, record);
      }
    }

    _notifyChange();
    return item;
  }

  /// Update an existing item.
  ///
  /// The item is identified by its ID. The entire payload is replaced.
  /// Returns the updated item.
  ///
  /// Throws [NativeStoreException] if the item doesn't exist or version mismatch.
  /// Throws [OperationCancelledException] if a beforeUpdate hook returns false.
  T update(T item) {
    final id = _getId(item);
    final existingJson = _store.get(_name, id);
    if (existingJson == null) {
      throw NativeStoreException('Record not found: $id');
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final existingRecord = Record.fromJson(existingJson);

    // Call beforeUpdate hook
    if (_hooks.beforeUpdate != null) {
      final ctx = OperationContext<T>(
        collection: _name,
        recordId: id,
        item: item,
        existingRecord: existingRecord,
        timestamp: timestamp,
      );
      if (!_hooks.beforeUpdate!(ctx)) {
        throw OperationCancelledException(
          operation: 'update',
          collection: _name,
          recordId: id,
        );
      }
    }

    final payload = _toJson(item);
    final opId = _generateOpId();
    final baseVersion = existingJson['version'] as int;

    final op = UpdateOp(
      opId: opId,
      recordId: id,
      collection: _name,
      payload: payload,
      baseVersion: baseVersion,
      timestamp: timestamp,
      clock: _nextClock(),
    );

    _store.apply(op.toJson(), timestamp);

    // Call afterUpdate hook
    if (_hooks.afterUpdate != null) {
      final record = getRecord(id);
      if (record != null) {
        final ctx = OperationContext<T>(
          collection: _name,
          recordId: id,
          item: item,
          existingRecord: existingRecord,
          timestamp: timestamp,
        );
        _hooks.afterUpdate!(ctx, record);
      }
    }

    _notifyChange();
    return item;
  }

  /// Delete an item by ID.
  ///
  /// This performs a soft delete (tombstone).
  ///
  /// Throws [NativeStoreException] if the item doesn't exist.
  /// Throws [OperationCancelledException] if a beforeDelete hook returns false.
  void delete(String id) {
    final existingJson = _store.get(_name, id);
    if (existingJson == null) {
      throw NativeStoreException('Record not found: $id');
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final existingRecord = Record.fromJson(existingJson);

    // Call beforeDelete hook
    if (_hooks.beforeDelete != null) {
      final ctx = OperationContext<T>(
        collection: _name,
        recordId: id,
        existingRecord: existingRecord,
        timestamp: timestamp,
      );
      if (!_hooks.beforeDelete!(ctx)) {
        throw OperationCancelledException(
          operation: 'delete',
          collection: _name,
          recordId: id,
        );
      }
    }

    final opId = _generateOpId();
    final baseVersion = existingJson['version'] as int;

    final op = DeleteOp(
      opId: opId,
      recordId: id,
      collection: _name,
      baseVersion: baseVersion,
      timestamp: timestamp,
      clock: _nextClock(),
    );

    _store.apply(op.toJson(), timestamp);

    // Call afterDelete hook
    if (_hooks.afterDelete != null) {
      final ctx = OperationContext<T>(
        collection: _name,
        recordId: id,
        existingRecord: existingRecord,
        timestamp: timestamp,
      );
      _hooks.afterDelete!(ctx);
    }

    _notifyChange();
  }

  /// Get an item by ID.
  ///
  /// Returns null if not found or deleted.
  T? get(String id) {
    final record = _store.get(_name, id);
    if (record == null) {
      return null;
    }
    // Merge record id into payload for fromJson (id is stored at record level)
    final payload = Map<String, dynamic>.from(
      record['payload'] as Map<String, dynamic>,
    );
    payload['id'] = record['id'];
    return _fromJson(payload);
  }

  /// Get all active items in the collection.
  List<T> all() {
    final records = _store.query(_name);
    return records.map((r) {
      // Merge record id into payload for fromJson (id is stored at record level)
      final payload = Map<String, dynamic>.from(
        r['payload'] as Map<String, dynamic>,
      );
      payload['id'] = r['id'];
      return _fromJson(payload);
    }).toList();
  }

  /// Filter items using a predicate.
  List<T> where(bool Function(T) predicate) {
    return all().where(predicate).toList();
  }

  /// Get the raw record for an item by ID.
  ///
  /// Includes metadata and deleted records.
  Record? getRecord(String id) {
    final records = _store.query(_name, includeDeleted: true);
    for (final r in records) {
      if (r['id'] == id) {
        return Record.fromJson(r);
      }
    }
    return null;
  }

  /// Get all raw records including deleted ones.
  List<Record> allRecords({bool includeDeleted = false}) {
    final records = _store.query(_name, includeDeleted: includeDeleted);
    return records.map((r) => Record.fromJson(r)).toList();
  }

  /// Watch for changes to the collection.
  ///
  /// Emits the current list of items immediately, then whenever the collection changes.
  Stream<List<T>> watch() {
    // Emit current state immediately
    Future.microtask(() => _controller.add(all()));
    return _controller.stream;
  }

  /// The number of active items in the collection.
  int get length => all().length;

  /// Whether the collection is empty.
  bool get isEmpty => length == 0;

  /// Whether the collection is not empty.
  bool get isNotEmpty => !isEmpty;

  LogicalClock _nextClock() {
    final clockJson = _store.tick();
    return LogicalClock.fromJson(clockJson);
  }

  String _generateOpId() {
    _opCounter++;
    return '${_nodeId}_${DateTime.now().millisecondsSinceEpoch}_$_opCounter';
  }

  void _notifyChange() {
    if (_controller.hasListener) {
      _controller.add(all());
    }
  }

  /// Notify listeners of external changes (e.g., from sync).
  ///
  /// This is called by SyncStore after reconciliation to update watchers.
  void notifyListeners() => _notifyChange();

  /// Close the collection's stream controller.
  void dispose() => _controller.close();
}
