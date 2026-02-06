//! Integration tests for the sync protocol.
//!
//! These tests require a running PostgreSQL database.
//! Set DATABASE_URL environment variable before running.

use carry_engine::{CreateOp, LogicalClock, Operation};
use serde_json::json;

/// Test helper to create a test operation.
fn create_test_op(op_id: &str, record_id: &str, node_id: &str, counter: u64) -> Operation {
    Operation::Create(CreateOp::new(
        op_id,
        record_id,
        "todos",
        json!({"title": "Test todo", "completed": false}),
        1706745600000 + counter * 1000, // timestamp
        LogicalClock::with_counter(node_id, counter),
    ))
}

#[cfg(test)]
mod protocol_tests {
    use super::*;

    #[test]
    fn test_operation_serialization() {
        let op = create_test_op("op-1", "todo-1", "device-1", 1);

        let json = serde_json::to_string(&op).unwrap();
        let parsed: Operation = serde_json::from_str(&json).unwrap();

        assert_eq!(op.op_id(), parsed.op_id());
        assert_eq!(op.record_id(), parsed.record_id());
        assert_eq!(op.collection(), parsed.collection());
    }

    #[test]
    fn test_operation_ordering() {
        let op1 = create_test_op("op-1", "todo-1", "device-1", 1);
        let op2 = create_test_op("op-2", "todo-2", "device-1", 2);

        // op2 has higher clock counter than op1
        assert!(op1 < op2);

        // op1 and op3 have same counter, but different timestamps
        // op1 timestamp: 1706745601000, op3 timestamp: 1706745601000
        // Same timestamp, so it falls back to op_id comparison
    }

    #[test]
    fn test_conflict_resolution_clock_wins() {
        use carry_engine::{
            CollectionSchema, FieldDef, FieldType, MergeStrategy, Reconciler, Schema,
        };

        let schema = Schema::new(1).with_collection(CollectionSchema::new(
            "todos",
            vec![
                FieldDef::optional("title", FieldType::String),
                FieldDef::optional("completed", FieldType::Bool),
            ],
        ));

        let reconciler = Reconciler::new(&schema, MergeStrategy::ClockWins);

        // Two devices create the same record
        let local_op = create_test_op("op-local", "todo-1", "device-1", 5);
        let remote_op = create_test_op("op-remote", "todo-1", "device-2", 10);

        let (result, records) = reconciler.reconcile(vec![local_op], vec![remote_op]);

        // Remote should win (higher clock counter)
        assert_eq!(result.conflicts.len(), 1);
        assert!(result.rejected_local.contains(&"op-local".to_string()));
        assert!(result.applied_remote.contains(&"op-remote".to_string()));

        // Verify final record
        let record = records
            .get(&("todos".to_string(), "todo-1".to_string()))
            .unwrap();
        assert_eq!(record.metadata.clock.counter, 10);
    }

    #[test]
    fn test_no_conflict_different_records() {
        use carry_engine::{
            CollectionSchema, FieldDef, FieldType, MergeStrategy, Reconciler, Schema,
        };

        let schema = Schema::new(1).with_collection(CollectionSchema::new(
            "todos",
            vec![
                FieldDef::optional("title", FieldType::String),
                FieldDef::optional("completed", FieldType::Bool),
            ],
        ));

        let reconciler = Reconciler::new(&schema, MergeStrategy::ClockWins);

        // Two devices create different records
        let local_op = create_test_op("op-local", "todo-1", "device-1", 1);
        let remote_op = create_test_op("op-remote", "todo-2", "device-2", 1);

        let (result, records) = reconciler.reconcile(vec![local_op], vec![remote_op]);

        // No conflicts, both accepted
        assert_eq!(result.conflicts.len(), 0);
        assert!(result.accepted_local.contains(&"op-local".to_string()));
        assert!(result.applied_remote.contains(&"op-remote".to_string()));
        assert_eq!(records.len(), 2);
    }

    #[test]
    fn test_sync_token_format() {
        // Sync token format: "timestamp_opId"
        let token = "1706745600000_op-123";
        let parts: Vec<&str> = token.splitn(2, '_').collect();

        assert_eq!(parts.len(), 2);
        assert_eq!(parts[0], "1706745600000");
        assert_eq!(parts[1], "op-123");

        let timestamp: i64 = parts[0].parse().unwrap();
        assert_eq!(timestamp, 1706745600000);
    }

    #[test]
    fn test_push_request_deserialization() {
        let json = r#"{
            "nodeId": "device-123",
            "operations": [
                {
                    "type": "create",
                    "opId": "op-1",
                    "id": "todo-1",
                    "collection": "todos",
                    "payload": {"title": "Test", "completed": false},
                    "timestamp": 1706745600000,
                    "clock": {"nodeId": "device-123", "counter": 1}
                }
            ]
        }"#;

        #[derive(serde::Deserialize)]
        #[serde(rename_all = "camelCase")]
        struct PushRequest {
            node_id: String,
            operations: Vec<Operation>,
        }

        let request: PushRequest = serde_json::from_str(json).unwrap();

        assert_eq!(request.node_id, "device-123");
        assert_eq!(request.operations.len(), 1);
        assert_eq!(request.operations[0].op_id(), "op-1");
    }

    #[test]
    fn test_pull_response_serialization() {
        let ops = vec![create_test_op("op-1", "todo-1", "device-1", 1)];

        #[derive(serde::Serialize)]
        #[serde(rename_all = "camelCase")]
        struct PullResponse {
            operations: Vec<Operation>,
            sync_token: String,
            has_more: bool,
        }

        let response = PullResponse {
            operations: ops,
            sync_token: "1706745601000_op-1".to_string(),
            has_more: false,
        };

        let json = serde_json::to_string(&response).unwrap();

        assert!(json.contains("\"syncToken\":\"1706745601000_op-1\""));
        assert!(json.contains("\"hasMore\":false"));
    }
}
