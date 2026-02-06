//! Edge case tests for carry-engine
//!
//! These tests cover boundary conditions and unusual inputs.

use carry_engine::{
    CollectionSchema, CreateOp, DeleteOp, FieldDef, FieldType, LogicalClock, MergeStrategy,
    Operation, Schema, Store, StoreSnapshot, UpdateOp,
};
use serde_json::json;

fn create_test_schema() -> Schema {
    let mut schema = Schema::new(1);
    let fields = vec![
        FieldDef::required("name", FieldType::String),
        FieldDef::optional("count", FieldType::Int),
        FieldDef::optional("data", FieldType::Json),
    ];
    let collection = CollectionSchema::new("items", fields);
    schema.add_collection(collection);
    schema
}

// ============================================================================
// String Edge Cases
// ============================================================================

#[test]
fn empty_string_fields() {
    let schema = create_test_schema();
    let mut store = Store::new(schema, "node1".to_string());

    let op = Operation::Create(CreateOp::new(
        "op1",
        "item1",
        "items",
        json!({"name": ""}), // Empty string
        1000,
        LogicalClock::with_counter("node1", 1),
    ));

    let result = store.apply(op, 1000);
    assert!(result.is_ok());

    let record = store.get("items", "item1").unwrap();
    assert_eq!(record.payload["name"], "");
}

#[test]
fn unicode_strings() {
    let schema = create_test_schema();
    let mut store = Store::new(schema, "node1".to_string());

    // Various unicode strings
    let unicode_names = vec![
        "日本語テスト",      // Japanese
        "Привет мир",        // Russian
        "مرحبا بالعالم",     // Arabic
        "🎉🚀💯",            // Emoji
        "Ω≈ç√∫",             // Math symbols
        "Hello\nWorld\tTab", // Whitespace
        "Null\0Test",        // Embedded null
    ];

    for (i, name) in unicode_names.iter().enumerate() {
        let op = Operation::Create(CreateOp::new(
            format!("op_{}", i),
            format!("item_{}", i),
            "items",
            json!({"name": name}),
            1000,
            LogicalClock::with_counter("node1", i as u64),
        ));

        let result = store.apply(op, 1000);
        assert!(result.is_ok(), "Failed for: {}", name);

        let record = store.get("items", &format!("item_{}", i)).unwrap();
        assert_eq!(record.payload["name"], *name);
    }
}

#[test]
fn very_long_strings() {
    let schema = create_test_schema();
    let mut store = Store::new(schema, "node1".to_string());

    // 1MB string
    let long_string = "x".repeat(1024 * 1024);

    let op = Operation::Create(CreateOp::new(
        "op1",
        "item1",
        "items",
        json!({"name": long_string.clone()}),
        1000,
        LogicalClock::with_counter("node1", 1),
    ));

    let result = store.apply(op, 1000);
    assert!(result.is_ok());

    let record = store.get("items", "item1").unwrap();
    assert_eq!(record.payload["name"].as_str().unwrap().len(), 1024 * 1024);
}

// ============================================================================
// Numeric Edge Cases
// ============================================================================

#[test]
fn integer_boundaries() {
    let schema = create_test_schema();
    let mut store = Store::new(schema, "node1".to_string());

    let values = vec![i64::MIN, i64::MAX, 0i64, -1i64, 1i64];

    for (i, value) in values.iter().enumerate() {
        let op = Operation::Create(CreateOp::new(
            format!("op_{}", i),
            format!("item_{}", i),
            "items",
            json!({"name": "test", "count": value}),
            1000,
            LogicalClock::with_counter("node1", i as u64),
        ));

        let result = store.apply(op, 1000);
        assert!(result.is_ok());

        let record = store.get("items", &format!("item_{}", i)).unwrap();
        assert_eq!(record.payload["count"], *value);
    }
}

#[test]
fn clock_counter_high_values() {
    // Test with very high counter values
    let mut clock = LogicalClock::with_counter("node", u64::MAX - 1);
    clock.tick();
    assert_eq!(clock.counter, u64::MAX);
}

// ============================================================================
// JSON Edge Cases
// ============================================================================

#[test]
fn deeply_nested_json() {
    let schema = create_test_schema();
    let mut store = Store::new(schema, "node1".to_string());

    // Create deeply nested JSON (50 levels)
    let mut nested = json!({"value": "leaf"});
    for _ in 0..50 {
        nested = json!({"nested": nested});
    }

    let op = Operation::Create(CreateOp::new(
        "op1",
        "item1",
        "items",
        json!({"name": "test", "data": nested}),
        1000,
        LogicalClock::with_counter("node1", 1),
    ));

    let result = store.apply(op, 1000);
    assert!(result.is_ok());
}

#[test]
fn json_with_all_types() {
    let schema = create_test_schema();
    let mut store = Store::new(schema, "node1".to_string());

    let complex_json = json!({
        "string": "hello",
        "number": 42,
        "float": 3.14159,
        "bool_true": true,
        "bool_false": false,
        "null": null,
        "array": [1, 2, 3, "mixed", true, null],
        "object": {"a": 1, "b": "two"},
        "empty_array": [],
        "empty_object": {},
    });

    let op = Operation::Create(CreateOp::new(
        "op1",
        "item1",
        "items",
        json!({"name": "test", "data": complex_json.clone()}),
        1000,
        LogicalClock::with_counter("node1", 1),
    ));

    let result = store.apply(op, 1000);
    assert!(result.is_ok());

    let record = store.get("items", "item1").unwrap();
    assert_eq!(record.payload["data"], complex_json);
}

// ============================================================================
// Operation Ordering Edge Cases
// ============================================================================

#[test]
fn same_timestamp_same_counter_different_nodes() {
    let schema = create_test_schema();
    let mut store = Store::new(schema, "node_a".to_string());

    // Create ops with same timestamp and counter but different node IDs
    let op_a = Operation::Create(CreateOp::new(
        "op_a",
        "item1",
        "items",
        json!({"name": "from_a"}),
        1000,
        LogicalClock::with_counter("node_a", 1),
    ));

    let op_b = Operation::Create(CreateOp::new(
        "op_b",
        "item1",
        "items",
        json!({"name": "from_b"}),
        1000,
        LogicalClock::with_counter("node_b", 1),
    ));

    // Apply op_a first
    let result = store.apply(op_a, 1000);
    assert!(result.is_ok());

    // Reconcile with op_b (should resolve deterministically by node_id)
    let _reconcile_result = store.reconcile(vec![op_b], MergeStrategy::ClockWins);

    // The result should be deterministic - node_b wins alphabetically
    let record = store.get("items", "item1").unwrap();
    assert_eq!(record.payload["name"], "from_b");
}

#[test]
fn rapid_updates_same_record() {
    let schema = create_test_schema();
    let mut store = Store::new(schema, "node1".to_string());

    // Create initial record
    let create_op = Operation::Create(CreateOp::new(
        "create",
        "item1",
        "items",
        json!({"name": "initial"}),
        1000,
        LogicalClock::with_counter("node1", 0),
    ));
    store.apply(create_op, 1000).unwrap();

    // Apply 100 rapid updates
    // After create, version is 1. Each update increments it.
    for i in 1..=100 {
        let update_op = Operation::Update(UpdateOp::new(
            format!("update_{}", i),
            "item1",
            "items",
            json!({"name": format!("update_{}", i)}),
            i as u64, // Expected version (starts at 1 after create)
            1000 + i as u64,
            LogicalClock::with_counter("node1", i as u64),
        ));

        let result = store.apply(update_op, 1000 + i as u64);
        assert!(result.is_ok(), "Update {} failed", i);
    }

    let record = store.get("items", "item1").unwrap();
    // Version starts at 1 after create, then +1 for each of 100 updates = 101
    assert_eq!(record.version, 101);
    assert_eq!(record.payload["name"], "update_100");
}

// ============================================================================
// Reconciliation Edge Cases
// ============================================================================

#[test]
fn reconcile_empty_remote_ops() {
    let schema = create_test_schema();
    let mut store = Store::new(schema, "node1".to_string());

    // Add local data
    let op = Operation::Create(CreateOp::new(
        "op1",
        "item1",
        "items",
        json!({"name": "local"}),
        1000,
        LogicalClock::with_counter("node1", 1),
    ));
    store.apply(op, 1000).unwrap();

    // Reconcile with empty remote
    let result = store.reconcile(vec![], MergeStrategy::ClockWins);
    assert!(result.conflicts.is_empty());
    assert!(result.rejected_remote.is_empty());
}

#[test]
fn reconcile_delete_vs_update() {
    let schema = create_test_schema();
    let mut store = Store::new(schema, "local".to_string());

    // Create record locally
    let create_op = Operation::Create(CreateOp::new(
        "create",
        "item1",
        "items",
        json!({"name": "initial"}),
        1000,
        LogicalClock::with_counter("local", 1),
    ));
    store.apply(create_op, 1000).unwrap();
    store.clear_pending();

    // Local: delete (version is 1 after create)
    let delete_op = Operation::Delete(DeleteOp::new(
        "delete_local",
        "item1",
        "items",
        1, // Version after create
        2000,
        LogicalClock::with_counter("local", 10), // Higher counter
    ));
    store.apply(delete_op, 2000).unwrap();

    // Remote: update with lower clock
    let update_op = Operation::Update(UpdateOp::new(
        "update_remote",
        "item1",
        "items",
        json!({"name": "updated"}),
        1, // Version after create
        2500,
        LogicalClock::with_counter("remote", 5), // Lower counter
    ));

    let _result = store.reconcile(vec![update_op], MergeStrategy::ClockWins);

    // Delete should win because it has higher clock counter
    // Use get_including_deleted since deleted records are filtered by default
    let record = store.get_including_deleted("items", "item1").unwrap();
    assert!(record.deleted);
}

// ============================================================================
// Snapshot Edge Cases
// ============================================================================

#[test]
fn snapshot_empty_store() {
    let schema = create_test_schema();
    let store = Store::new(schema, "node1".to_string());

    let snapshot = store.export_state();
    assert_eq!(snapshot.record_count(), 0);
    assert_eq!(snapshot.active_record_count(), 0);

    // Re-import
    let schema2 = create_test_schema();
    let mut store2 = Store::new(schema2, "node1".to_string());
    assert!(store2.import_state(snapshot).is_ok());
}

#[test]
fn snapshot_with_deleted_records() {
    let schema = create_test_schema();
    let mut store = Store::new(schema, "node1".to_string());

    // Create and delete some records
    for i in 0..10u64 {
        let create_op = Operation::Create(CreateOp::new(
            format!("create_{}", i),
            format!("item_{}", i),
            "items",
            json!({"name": format!("item_{}", i)}),
            1000,
            LogicalClock::with_counter("node1", i * 2),
        ));
        store.apply(create_op, 1000).unwrap();

        if i % 2 == 0 {
            let delete_op = Operation::Delete(DeleteOp::new(
                format!("delete_{}", i),
                format!("item_{}", i),
                "items",
                1, // Version after create
                2000,
                LogicalClock::with_counter("node1", i * 2 + 1),
            ));
            store.apply(delete_op, 2000).unwrap();
        }
    }

    let snapshot = store.export_state();
    assert_eq!(snapshot.record_count(), 10);
    assert_eq!(snapshot.active_record_count(), 5); // Half deleted

    // Verify JSON roundtrip preserves deleted state
    let json = snapshot.to_json().unwrap();
    let restored = StoreSnapshot::from_json(&json).unwrap();
    assert_eq!(restored.active_record_count(), 5);
}

// ============================================================================
// Schema Edge Cases
// ============================================================================

#[test]
fn schema_with_many_collections() {
    let mut schema = Schema::new(1);

    // Add 100 collections
    for i in 0..100 {
        let fields = vec![FieldDef::required("id", FieldType::String)];
        let collection = CollectionSchema::new(format!("collection_{}", i), fields);
        schema.add_collection(collection);
    }

    let mut store = Store::new(schema, "node1".to_string());

    // Add records to various collections
    for i in 0..100u64 {
        let op = Operation::Create(CreateOp::new(
            format!("op_{}", i),
            format!("record_{}", i),
            format!("collection_{}", i % 100),
            json!({"id": format!("id_{}", i)}),
            1000,
            LogicalClock::with_counter("node1", i),
        ));
        assert!(store.apply(op, 1000).is_ok());
    }

    // Verify we can query each collection
    for i in 0..100 {
        let records = store
            .query(&format!("collection_{}", i))
            .expect("collection should exist")
            .all();
        assert_eq!(records.len(), 1);
    }
}

#[test]
fn field_with_special_characters_in_name() {
    let mut schema = Schema::new(1);
    let fields = vec![
        FieldDef::optional("with-dash", FieldType::String),
        FieldDef::optional("with_underscore", FieldType::String),
        FieldDef::optional("with.dot", FieldType::String),
        FieldDef::optional("with spaces", FieldType::String),
        FieldDef::optional("123numeric", FieldType::String),
    ];
    let collection = CollectionSchema::new("items", fields);
    schema.add_collection(collection);

    let mut store = Store::new(schema, "node1".to_string());

    let op = Operation::Create(CreateOp::new(
        "op1",
        "item1",
        "items",
        json!({
            "with-dash": "a",
            "with_underscore": "b",
            "with.dot": "c",
            "with spaces": "d",
            "123numeric": "e"
        }),
        1000,
        LogicalClock::with_counter("node1", 1),
    ));

    assert!(store.apply(op, 1000).is_ok());
}

// ============================================================================
// Concurrent Operations
// ============================================================================

#[test]
fn many_pending_operations() {
    let schema = create_test_schema();
    let mut store = Store::new(schema, "node1".to_string());

    // Create 1000 records, all pending
    for i in 0..1000u64 {
        let op = Operation::Create(CreateOp::new(
            format!("op_{}", i),
            format!("item_{}", i),
            "items",
            json!({"name": format!("item_{}", i)}),
            1000 + i,
            LogicalClock::with_counter("node1", i),
        ));
        store.apply(op, 1000 + i).unwrap();
    }

    assert_eq!(store.pending_ops().len(), 1000);

    // Acknowledge half
    let ids_to_ack: Vec<_> = (0..500).map(|i| format!("op_{}", i)).collect();
    store.acknowledge(&ids_to_ack);

    assert_eq!(store.pending_ops().len(), 500);
}

// ============================================================================
// ID Edge Cases
// ============================================================================

#[test]
fn ids_with_special_characters() {
    let schema = create_test_schema();
    let mut store = Store::new(schema, "node1".to_string());

    let special_ids = vec![
        "simple",
        "with-dash",
        "with_underscore",
        "with.dots",
        "with/slash",
        "with:colon",
        "with@at",
        "with#hash",
        "uuid-style-550e8400-e29b-41d4-a716-446655440000",
        "emoji-🎉",
        "space test",
        "newline\ntest",
        "", // Empty ID
    ];

    for (i, id) in special_ids.iter().enumerate() {
        let op = Operation::Create(CreateOp::new(
            format!("op_{}", i),
            id.to_string(),
            "items",
            json!({"name": "test"}),
            1000,
            LogicalClock::with_counter("node1", i as u64),
        ));

        let result = store.apply(op, 1000);
        assert!(result.is_ok(), "Failed for ID: {:?}", id);

        // Verify we can retrieve it
        let record = store.get("items", id);
        assert!(record.is_some(), "Could not retrieve ID: {:?}", id);
    }
}
