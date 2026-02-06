//! FFI layer for Flutter integration.
//!
//! This module provides C-compatible functions that can be called via Dart FFI.
//! All data crosses the boundary as JSON strings.
//!
//! # Memory Management
//!
//! - Strings returned by `carry_*` functions are allocated by Rust
//! - Caller must free them with `carry_string_free`
//! - Store pointers must be freed with `carry_store_free`
//!
//! # Error Handling
//!
//! Functions return JSON with either:
//! - `{"ok": <result>}` on success
//! - `{"error": "<message>"}` on failure

use crate::{reconcile::MergeStrategy, Operation, Schema, Store, StoreSnapshot};
use std::ffi::{c_char, CStr, CString};
use std::ptr;

/// Result wrapper for FFI responses.
#[derive(serde::Serialize)]
#[serde(untagged)]
enum FfiResult<T: serde::Serialize> {
    Ok { ok: T },
    Err { error: String },
}

impl<T: serde::Serialize> FfiResult<T> {
    fn ok(value: T) -> Self {
        FfiResult::Ok { ok: value }
    }

    fn err(message: impl Into<String>) -> Self {
        FfiResult::Err {
            error: message.into(),
        }
    }

    fn to_json(&self) -> String {
        serde_json::to_string(self)
            .unwrap_or_else(|e| format!(r#"{{"error":"serialization failed: {}"}}"#, e))
    }
}

/// Convert a Rust string to a C string pointer.
/// Caller must free with `carry_string_free`.
fn to_c_string(s: String) -> *mut c_char {
    match CString::new(s) {
        Ok(cs) => cs.into_raw(),
        Err(_) => {
            // String contained null bytes - return error JSON
            let error = CString::new(r#"{"error":"string contained null bytes"}"#).unwrap();
            error.into_raw()
        }
    }
}

/// Convert a C string pointer to a Rust string.
/// Returns None if pointer is null or invalid UTF-8.
unsafe fn from_c_string(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    CStr::from_ptr(ptr).to_str().ok().map(|s| s.to_string())
}

// ============================================================================
// Store Lifecycle
// ============================================================================

/// Create a new store.
///
/// # Arguments
/// - `schema_json`: JSON string of Schema
/// - `node_id`: Node identifier string
///
/// # Returns
/// Pointer to Store, or null on failure.
///
/// # Safety
/// - `schema_json` must be a valid null-terminated C string or null
/// - `node_id` must be a valid null-terminated C string or null
/// - Caller must free the returned pointer with `carry_store_free`
#[no_mangle]
pub unsafe extern "C" fn carry_store_new(
    schema_json: *const c_char,
    node_id: *const c_char,
) -> *mut Store {
    let schema_str = match from_c_string(schema_json) {
        Some(s) => s,
        None => return ptr::null_mut(),
    };

    let node_id_str = match from_c_string(node_id) {
        Some(s) => s,
        None => return ptr::null_mut(),
    };

    let schema: Schema = match serde_json::from_str(&schema_str) {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };

    let store = Store::new(schema, node_id_str);
    Box::into_raw(Box::new(store))
}

/// Free a store.
///
/// # Safety
/// - `store` must be a valid pointer from `carry_store_new`
/// - Must not be called twice on the same pointer
#[no_mangle]
pub unsafe extern "C" fn carry_store_free(store: *mut Store) {
    if !store.is_null() {
        drop(Box::from_raw(store));
    }
}

/// Free a string allocated by the engine.
///
/// # Safety
/// - `s` must be a valid pointer from a `carry_*` function
/// - Must not be called twice on the same pointer
#[no_mangle]
pub unsafe extern "C" fn carry_string_free(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}

// ============================================================================
// Store Operations
// ============================================================================

/// Apply an operation to the store.
///
/// # Arguments
/// - `store`: Store pointer
/// - `op_json`: JSON string of Operation
/// - `timestamp`: Timestamp in milliseconds
///
/// # Returns
/// JSON string: `{"ok": ApplyResult}` or `{"error": "message"}`
///
/// # Safety
/// - `store` must be a valid pointer from `carry_store_new` or null
/// - `op_json` must be a valid null-terminated C string or null
/// - Caller must free the returned string with `carry_string_free`
#[no_mangle]
pub unsafe extern "C" fn carry_store_apply(
    store: *mut Store,
    op_json: *const c_char,
    timestamp: u64,
) -> *mut c_char {
    let store = match store.as_mut() {
        Some(s) => s,
        None => return to_c_string(FfiResult::<()>::err("null store pointer").to_json()),
    };

    let op_str = match from_c_string(op_json) {
        Some(s) => s,
        None => return to_c_string(FfiResult::<()>::err("invalid operation JSON").to_json()),
    };

    let op: Operation = match serde_json::from_str(&op_str) {
        Ok(o) => o,
        Err(e) => {
            return to_c_string(FfiResult::<()>::err(format!("parse error: {}", e)).to_json())
        }
    };

    match store.apply(op, timestamp) {
        Ok(result) => to_c_string(FfiResult::ok(result).to_json()),
        Err(e) => to_c_string(FfiResult::<()>::err(e.to_string()).to_json()),
    }
}

/// Get a record by collection and ID.
///
/// # Returns
/// JSON string: `{"ok": Record}` or `{"ok": null}` or `{"error": "message"}`
///
/// # Safety
/// - `store` must be a valid pointer from `carry_store_new` or null
/// - `collection` and `id` must be valid null-terminated C strings or null
/// - Caller must free the returned string with `carry_string_free`
#[no_mangle]
pub unsafe extern "C" fn carry_store_get(
    store: *const Store,
    collection: *const c_char,
    id: *const c_char,
) -> *mut c_char {
    let store = match store.as_ref() {
        Some(s) => s,
        None => return to_c_string(FfiResult::<()>::err("null store pointer").to_json()),
    };

    let collection_str = match from_c_string(collection) {
        Some(s) => s,
        None => return to_c_string(FfiResult::<()>::err("invalid collection").to_json()),
    };

    let id_str = match from_c_string(id) {
        Some(s) => s,
        None => return to_c_string(FfiResult::<()>::err("invalid id").to_json()),
    };

    let record = store.get(&collection_str, &id_str);
    to_c_string(FfiResult::ok(record).to_json())
}

/// Query all records in a collection.
///
/// # Arguments
/// - `include_deleted`: 0 for active only, non-zero for all
///
/// # Returns
/// JSON string: `{"ok": [Record, ...]}` or `{"error": "message"}`
///
/// # Safety
/// - `store` must be a valid pointer from `carry_store_new` or null
/// - `collection` must be a valid null-terminated C string or null
/// - Caller must free the returned string with `carry_string_free`
#[no_mangle]
pub unsafe extern "C" fn carry_store_query(
    store: *const Store,
    collection: *const c_char,
    include_deleted: i32,
) -> *mut c_char {
    let store = match store.as_ref() {
        Some(s) => s,
        None => return to_c_string(FfiResult::<()>::err("null store pointer").to_json()),
    };

    let collection_str = match from_c_string(collection) {
        Some(s) => s,
        None => return to_c_string(FfiResult::<()>::err("invalid collection").to_json()),
    };

    let query = match store.query(&collection_str) {
        Some(q) => q,
        None => return to_c_string(FfiResult::<()>::err("collection not found").to_json()),
    };

    let records: Vec<_> = if include_deleted != 0 {
        query.include_deleted().all()
    } else {
        query.all()
    };

    to_c_string(FfiResult::ok(records).to_json())
}

/// Get pending operations count.
///
/// # Safety
/// - `store` must be a valid pointer from `carry_store_new` or null
#[no_mangle]
pub unsafe extern "C" fn carry_store_pending_count(store: *const Store) -> i64 {
    match store.as_ref() {
        Some(s) => s.pending_count() as i64,
        None => -1,
    }
}

/// Get pending operations.
///
/// # Returns
/// JSON string: `{"ok": [PendingOp, ...]}` or `{"error": "message"}`
///
/// # Safety
/// - `store` must be a valid pointer from `carry_store_new` or null
/// - Caller must free the returned string with `carry_string_free`
#[no_mangle]
pub unsafe extern "C" fn carry_store_pending_ops(store: *const Store) -> *mut c_char {
    let store = match store.as_ref() {
        Some(s) => s,
        None => return to_c_string(FfiResult::<()>::err("null store pointer").to_json()),
    };

    to_c_string(FfiResult::ok(store.pending_ops()).to_json())
}

/// Acknowledge operations as synced.
///
/// # Arguments
/// - `op_ids_json`: JSON array of operation IDs
///
/// # Safety
/// - `store` must be a valid pointer from `carry_store_new` or null
/// - `op_ids_json` must be a valid null-terminated C string or null
/// - Caller must free the returned string with `carry_string_free`
#[no_mangle]
pub unsafe extern "C" fn carry_store_acknowledge(
    store: *mut Store,
    op_ids_json: *const c_char,
) -> *mut c_char {
    let store = match store.as_mut() {
        Some(s) => s,
        None => return to_c_string(FfiResult::<()>::err("null store pointer").to_json()),
    };

    let op_ids_str = match from_c_string(op_ids_json) {
        Some(s) => s,
        None => return to_c_string(FfiResult::<()>::err("invalid op_ids JSON").to_json()),
    };

    let op_ids: Vec<String> = match serde_json::from_str(&op_ids_str) {
        Ok(ids) => ids,
        Err(e) => {
            return to_c_string(FfiResult::<()>::err(format!("parse error: {}", e)).to_json())
        }
    };

    store.acknowledge(&op_ids);
    to_c_string(FfiResult::ok(()).to_json())
}

/// Tick the store clock and return the new clock value.
///
/// # Returns
/// JSON string: `{"ok": LogicalClock}` or `{"error": "message"}`
///
/// # Safety
/// - `store` must be a valid pointer from `carry_store_new` or null
/// - Caller must free the returned string with `carry_string_free`
#[no_mangle]
pub unsafe extern "C" fn carry_store_tick(store: *mut Store) -> *mut c_char {
    let store = match store.as_mut() {
        Some(s) => s,
        None => return to_c_string(FfiResult::<()>::err("null store pointer").to_json()),
    };

    let clock = store.tick();
    to_c_string(FfiResult::ok(clock).to_json())
}

// ============================================================================
// Reconciliation
// ============================================================================

/// Reconcile local pending operations with remote operations.
///
/// # Arguments
/// - `remote_ops_json`: JSON array of remote Operations
/// - `strategy`: 0 for ClockWins (default), 1 for TimestampWins
///
/// # Returns
/// JSON string: `{"ok": ReconcileResult}` or `{"error": "message"}`
///
/// # Safety
/// - `store` must be a valid pointer from `carry_store_new` or null
/// - `remote_ops_json` must be a valid null-terminated C string or null
/// - Caller must free the returned string with `carry_string_free`
#[no_mangle]
pub unsafe extern "C" fn carry_store_reconcile(
    store: *mut Store,
    remote_ops_json: *const c_char,
    strategy: i32,
) -> *mut c_char {
    let store = match store.as_mut() {
        Some(s) => s,
        None => return to_c_string(FfiResult::<()>::err("null store pointer").to_json()),
    };

    let remote_ops_str = match from_c_string(remote_ops_json) {
        Some(s) => s,
        None => return to_c_string(FfiResult::<()>::err("invalid remote_ops JSON").to_json()),
    };

    let remote_ops: Vec<Operation> = match serde_json::from_str(&remote_ops_str) {
        Ok(ops) => ops,
        Err(e) => {
            return to_c_string(FfiResult::<()>::err(format!("parse error: {}", e)).to_json())
        }
    };

    let merge_strategy = if strategy == 1 {
        MergeStrategy::TimestampWins
    } else {
        MergeStrategy::ClockWins
    };

    let result = store.reconcile(remote_ops, merge_strategy);
    to_c_string(FfiResult::ok(result).to_json())
}

// ============================================================================
// Snapshots
// ============================================================================

/// Export store state as a snapshot.
///
/// # Returns
/// JSON string: `{"ok": StoreSnapshot}` or `{"error": "message"}`
///
/// # Safety
/// - `store` must be a valid pointer from `carry_store_new` or null
/// - Caller must free the returned string with `carry_string_free`
#[no_mangle]
pub unsafe extern "C" fn carry_store_export(store: *const Store) -> *mut c_char {
    let store = match store.as_ref() {
        Some(s) => s,
        None => return to_c_string(FfiResult::<()>::err("null store pointer").to_json()),
    };

    let snapshot = store.export_state();
    to_c_string(FfiResult::ok(snapshot).to_json())
}

/// Import state from a snapshot.
///
/// # Arguments
/// - `snapshot_json`: JSON string of StoreSnapshot
///
/// # Returns
/// JSON string: `{"ok": null}` or `{"error": "message"}`
///
/// # Safety
/// - `store` must be a valid pointer from `carry_store_new` or null
/// - `snapshot_json` must be a valid null-terminated C string or null
/// - Caller must free the returned string with `carry_string_free`
#[no_mangle]
pub unsafe extern "C" fn carry_store_import(
    store: *mut Store,
    snapshot_json: *const c_char,
) -> *mut c_char {
    let store = match store.as_mut() {
        Some(s) => s,
        None => return to_c_string(FfiResult::<()>::err("null store pointer").to_json()),
    };

    let snapshot_str = match from_c_string(snapshot_json) {
        Some(s) => s,
        None => return to_c_string(FfiResult::<()>::err("invalid snapshot JSON").to_json()),
    };

    let snapshot: StoreSnapshot = match serde_json::from_str(&snapshot_str) {
        Ok(s) => s,
        Err(e) => {
            return to_c_string(FfiResult::<()>::err(format!("parse error: {}", e)).to_json())
        }
    };

    match store.import_state(snapshot) {
        Ok(()) => to_c_string(FfiResult::ok(()).to_json()),
        Err(e) => to_c_string(FfiResult::<()>::err(e.to_string()).to_json()),
    }
}

/// Get snapshot metadata without full export.
///
/// # Returns
/// JSON string: `{"ok": SnapshotMetadata}` or `{"error": "message"}`
///
/// # Safety
/// - `store` must be a valid pointer from `carry_store_new` or null
/// - Caller must free the returned string with `carry_string_free`
#[no_mangle]
pub unsafe extern "C" fn carry_store_metadata(store: *const Store) -> *mut c_char {
    let store = match store.as_ref() {
        Some(s) => s,
        None => return to_c_string(FfiResult::<()>::err("null store pointer").to_json()),
    };

    let metadata = store.snapshot_metadata();
    to_c_string(FfiResult::ok(metadata).to_json())
}

// ============================================================================
// Utility
// ============================================================================

/// Get the engine version.
///
/// # Returns
/// Static string pointer (do not free)
#[no_mangle]
pub extern "C" fn carry_version() -> *const c_char {
    static VERSION: &[u8] = concat!(env!("CARGO_PKG_VERSION"), "\0").as_bytes();
    VERSION.as_ptr() as *const c_char
}

/// Get the snapshot format version.
#[no_mangle]
pub extern "C" fn carry_snapshot_format_version() -> u32 {
    crate::SNAPSHOT_FORMAT_VERSION
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    fn test_schema_json() -> CString {
        CString::new(
            r#"{
                "version": 1,
                "collections": {
                    "users": {
                        "name": "users",
                        "fields": [
                            {"name": "name", "fieldType": "string", "required": true}
                        ]
                    }
                }
            }"#,
        )
        .unwrap()
    }

    fn test_node_id() -> CString {
        CString::new("test-node").unwrap()
    }

    #[test]
    fn ffi_store_lifecycle() {
        unsafe {
            let schema = test_schema_json();
            let node_id = test_node_id();

            let store = carry_store_new(schema.as_ptr(), node_id.as_ptr());
            assert!(!store.is_null());

            carry_store_free(store);
        }
    }

    #[test]
    fn ffi_store_apply_and_get() {
        unsafe {
            let schema = test_schema_json();
            let node_id = test_node_id();
            let store = carry_store_new(schema.as_ptr(), node_id.as_ptr());

            // Tick clock
            let clock_result = carry_store_tick(store);
            let clock_json = CStr::from_ptr(clock_result).to_str().unwrap();
            assert!(clock_json.contains("\"ok\""));
            carry_string_free(clock_result);

            // Apply create operation
            let op = CString::new(
                r#"{
                    "type": "create",
                    "opId": "op-1",
                    "id": "user-1",
                    "collection": "users",
                    "payload": {"name": "Alice"},
                    "timestamp": 1000,
                    "clock": {"nodeId": "test-node", "counter": 1}
                }"#,
            )
            .unwrap();

            let result = carry_store_apply(store, op.as_ptr(), 1000);
            let result_json = CStr::from_ptr(result).to_str().unwrap();
            assert!(result_json.contains("\"ok\""));
            assert!(result_json.contains("user-1"));
            carry_string_free(result);

            // Get the record
            let collection = CString::new("users").unwrap();
            let id = CString::new("user-1").unwrap();
            let get_result = carry_store_get(store, collection.as_ptr(), id.as_ptr());
            let get_json = CStr::from_ptr(get_result).to_str().unwrap();
            assert!(get_json.contains("Alice"));
            carry_string_free(get_result);

            carry_store_free(store);
        }
    }

    #[test]
    fn ffi_store_query() {
        unsafe {
            let schema = test_schema_json();
            let node_id = test_node_id();
            let store = carry_store_new(schema.as_ptr(), node_id.as_ptr());

            // Add a record
            let op = CString::new(
                r#"{
                    "type": "create",
                    "opId": "op-1",
                    "id": "user-1",
                    "collection": "users",
                    "payload": {"name": "Alice"},
                    "timestamp": 1000,
                    "clock": {"nodeId": "test-node", "counter": 1}
                }"#,
            )
            .unwrap();
            let result = carry_store_apply(store, op.as_ptr(), 1000);
            carry_string_free(result);

            // Query
            let collection = CString::new("users").unwrap();
            let query_result = carry_store_query(store, collection.as_ptr(), 0);
            let query_json = CStr::from_ptr(query_result).to_str().unwrap();
            assert!(query_json.contains("Alice"));
            carry_string_free(query_result);

            carry_store_free(store);
        }
    }

    #[test]
    fn ffi_store_pending() {
        unsafe {
            let schema = test_schema_json();
            let node_id = test_node_id();
            let store = carry_store_new(schema.as_ptr(), node_id.as_ptr());

            // Initially no pending
            assert_eq!(carry_store_pending_count(store), 0);

            // Add a record
            let op = CString::new(
                r#"{
                    "type": "create",
                    "opId": "op-1",
                    "id": "user-1",
                    "collection": "users",
                    "payload": {"name": "Alice"},
                    "timestamp": 1000,
                    "clock": {"nodeId": "test-node", "counter": 1}
                }"#,
            )
            .unwrap();
            let result = carry_store_apply(store, op.as_ptr(), 1000);
            carry_string_free(result);

            // Now has pending
            assert_eq!(carry_store_pending_count(store), 1);

            // Acknowledge
            let ack = CString::new(r#"["op-1"]"#).unwrap();
            let ack_result = carry_store_acknowledge(store, ack.as_ptr());
            carry_string_free(ack_result);

            assert_eq!(carry_store_pending_count(store), 0);

            carry_store_free(store);
        }
    }

    #[test]
    fn ffi_store_export_import() {
        unsafe {
            let schema = test_schema_json();
            let node_id = test_node_id();
            let store = carry_store_new(schema.as_ptr(), node_id.as_ptr());

            // Add a record
            let op = CString::new(
                r#"{
                    "type": "create",
                    "opId": "op-1",
                    "id": "user-1",
                    "collection": "users",
                    "payload": {"name": "Alice"},
                    "timestamp": 1000,
                    "clock": {"nodeId": "test-node", "counter": 1}
                }"#,
            )
            .unwrap();
            let result = carry_store_apply(store, op.as_ptr(), 1000);
            carry_string_free(result);

            // Export
            let export_result = carry_store_export(store);
            let export_json = CStr::from_ptr(export_result).to_str().unwrap();
            assert!(export_json.contains("Alice"));

            // Extract the snapshot from the result
            let parsed: serde_json::Value = serde_json::from_str(export_json).unwrap();
            let snapshot_json = serde_json::to_string(&parsed["ok"]).unwrap();
            carry_string_free(export_result);

            // Create new store and import
            let store2 = carry_store_new(schema.as_ptr(), node_id.as_ptr());
            let snapshot_cstr = CString::new(snapshot_json).unwrap();
            let import_result = carry_store_import(store2, snapshot_cstr.as_ptr());
            let import_json = CStr::from_ptr(import_result).to_str().unwrap();
            assert!(import_json.contains("\"ok\""));
            carry_string_free(import_result);

            // Verify data
            let collection = CString::new("users").unwrap();
            let id = CString::new("user-1").unwrap();
            let get_result = carry_store_get(store2, collection.as_ptr(), id.as_ptr());
            let get_json = CStr::from_ptr(get_result).to_str().unwrap();
            assert!(get_json.contains("Alice"));
            carry_string_free(get_result);

            carry_store_free(store);
            carry_store_free(store2);
        }
    }

    #[test]
    fn ffi_version() {
        unsafe {
            let version = carry_version();
            let version_str = CStr::from_ptr(version).to_str().unwrap();
            assert_eq!(version_str, env!("CARGO_PKG_VERSION"));
        }
    }

    #[test]
    fn ffi_error_handling() {
        unsafe {
            // Null store pointer
            let collection = CString::new("users").unwrap();
            let id = CString::new("user-1").unwrap();
            let result = carry_store_get(ptr::null(), collection.as_ptr(), id.as_ptr());
            let result_json = CStr::from_ptr(result).to_str().unwrap();
            assert!(result_json.contains("\"error\""));
            carry_string_free(result);

            // Invalid JSON
            let schema = test_schema_json();
            let node_id = test_node_id();
            let store = carry_store_new(schema.as_ptr(), node_id.as_ptr());

            let invalid_op = CString::new("not valid json").unwrap();
            let result = carry_store_apply(store, invalid_op.as_ptr(), 1000);
            let result_json = CStr::from_ptr(result).to_str().unwrap();
            assert!(result_json.contains("\"error\""));
            carry_string_free(result);

            carry_store_free(store);
        }
    }
}
