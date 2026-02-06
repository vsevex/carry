//! Unit tests for WebSocket protocol.

use carry_engine::{CreateOp, LogicalClock, Operation};
use serde_json::json;

/// Test helper to create a test operation.
fn create_test_op(op_id: &str, record_id: &str, node_id: &str, counter: u64) -> Operation {
    Operation::Create(CreateOp::new(
        op_id,
        record_id,
        "todos",
        json!({"title": "Test todo", "completed": false}),
        1706745600000 + counter * 1000,
        LogicalClock::with_counter(node_id, counter),
    ))
}

#[cfg(test)]
mod websocket_protocol_tests {
    use super::*;

    #[test]
    fn test_client_message_pull_deserialization() {
        let json = r#"{
            "type": "pull",
            "since": "1706745600_abc123",
            "limit": 50,
            "request_id": "req-001"
        }"#;

        #[derive(serde::Deserialize)]
        #[serde(tag = "type", rename_all = "snake_case")]
        #[allow(dead_code)]
        enum ClientMessage {
            Pull {
                since: Option<String>,
                limit: Option<i64>,
                request_id: Option<String>,
            },
            Push {
                node_id: String,
                operations: Vec<Operation>,
                request_id: Option<String>,
            },
            Ping,
        }

        let msg: ClientMessage = serde_json::from_str(json).unwrap();

        match msg {
            ClientMessage::Pull {
                since,
                limit,
                request_id,
            } => {
                assert_eq!(since, Some("1706745600_abc123".to_string()));
                assert_eq!(limit, Some(50));
                assert_eq!(request_id, Some("req-001".to_string()));
            }
            _ => panic!("Expected Pull message"),
        }
    }

    #[test]
    fn test_client_message_push_deserialization() {
        let json = r#"{
            "type": "push",
            "node_id": "device-123",
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
            ],
            "request_id": "req-002"
        }"#;

        #[derive(serde::Deserialize)]
        #[serde(tag = "type", rename_all = "snake_case")]
        #[allow(dead_code)]
        enum ClientMessage {
            Pull {
                since: Option<String>,
                limit: Option<i64>,
                request_id: Option<String>,
            },
            Push {
                node_id: String,
                operations: Vec<Operation>,
                request_id: Option<String>,
            },
            Ping,
        }

        let msg: ClientMessage = serde_json::from_str(json).unwrap();

        match msg {
            ClientMessage::Push {
                node_id,
                operations,
                request_id,
            } => {
                assert_eq!(node_id, "device-123");
                assert_eq!(operations.len(), 1);
                assert_eq!(operations[0].op_id(), "op-1");
                assert_eq!(request_id, Some("req-002".to_string()));
            }
            _ => panic!("Expected Push message"),
        }
    }

    #[test]
    fn test_client_message_ping_deserialization() {
        let json = r#"{"type": "ping"}"#;

        #[derive(serde::Deserialize, PartialEq, Debug)]
        #[serde(tag = "type", rename_all = "snake_case")]
        #[allow(dead_code)]
        enum ClientMessage {
            Pull {
                since: Option<String>,
                limit: Option<i64>,
                request_id: Option<String>,
            },
            Push {
                node_id: String,
                operations: Vec<Operation>,
                request_id: Option<String>,
            },
            Ping,
        }

        let msg: ClientMessage = serde_json::from_str(json).unwrap();

        assert!(matches!(msg, ClientMessage::Ping));
    }

    #[test]
    fn test_server_message_pull_response_serialization() {
        #[derive(serde::Serialize)]
        #[serde(tag = "type", rename_all = "snake_case")]
        #[allow(dead_code)]
        enum ServerMessage {
            PullResponse {
                operations: Vec<Operation>,
                sync_token: String,
                has_more: bool,
                #[serde(skip_serializing_if = "Option::is_none")]
                request_id: Option<String>,
            },
            Pong,
            Error {
                message: String,
                #[serde(skip_serializing_if = "Option::is_none")]
                request_id: Option<String>,
            },
        }

        let ops = vec![create_test_op("op-1", "todo-1", "device-1", 1)];

        let msg = ServerMessage::PullResponse {
            operations: ops,
            sync_token: "1706745601000_op-1".to_string(),
            has_more: false,
            request_id: Some("req-001".to_string()),
        };

        let json = serde_json::to_string(&msg).unwrap();

        assert!(json.contains(r#""type":"pull_response""#));
        assert!(json.contains(r#""sync_token":"1706745601000_op-1""#));
        assert!(json.contains(r#""has_more":false"#));
        assert!(json.contains(r#""request_id":"req-001""#));
    }

    #[test]
    fn test_server_message_pong_serialization() {
        #[derive(serde::Serialize)]
        #[serde(tag = "type", rename_all = "snake_case")]
        #[allow(dead_code)]
        enum ServerMessage {
            Pong,
            Error {
                message: String,
                #[serde(skip_serializing_if = "Option::is_none")]
                request_id: Option<String>,
            },
        }

        let msg = ServerMessage::Pong;
        let json = serde_json::to_string(&msg).unwrap();

        assert_eq!(json, r#"{"type":"pong"}"#);
    }

    #[test]
    fn test_server_message_error_serialization() {
        #[derive(serde::Serialize)]
        #[serde(tag = "type", rename_all = "snake_case")]
        #[allow(dead_code)]
        enum ServerMessage {
            Pong,
            Error {
                message: String,
                #[serde(skip_serializing_if = "Option::is_none")]
                request_id: Option<String>,
            },
        }

        let msg = ServerMessage::Error {
            message: "Invalid message format".to_string(),
            request_id: Some("req-003".to_string()),
        };

        let json = serde_json::to_string(&msg).unwrap();

        assert!(json.contains(r#""type":"error""#));
        assert!(json.contains(r#""message":"Invalid message format""#));
        assert!(json.contains(r#""request_id":"req-003""#));
    }

    #[test]
    fn test_server_message_ops_available_serialization() {
        #[derive(serde::Serialize)]
        #[serde(tag = "type", rename_all = "snake_case")]
        #[allow(dead_code)]
        enum ServerMessage {
            OpsAvailable {
                operations: Vec<Operation>,
                sync_token: String,
            },
        }

        let ops = vec![
            create_test_op("op-1", "todo-1", "device-1", 1),
            create_test_op("op-2", "todo-2", "device-1", 2),
        ];

        let msg = ServerMessage::OpsAvailable {
            operations: ops,
            sync_token: "1706745602000_op-2".to_string(),
        };

        let json = serde_json::to_string(&msg).unwrap();

        assert!(json.contains(r#""type":"ops_available""#));
        assert!(json.contains(r#""sync_token":"1706745602000_op-2""#));
    }

    #[test]
    fn test_push_response_with_rejected() {
        #[derive(serde::Serialize, serde::Deserialize)]
        #[serde(rename_all = "camelCase")]
        struct RejectedOp {
            op_id: String,
            reason: String,
            #[serde(skip_serializing_if = "Option::is_none")]
            winner: Option<String>,
        }

        #[derive(serde::Serialize)]
        #[serde(tag = "type", rename_all = "snake_case")]
        #[allow(dead_code)]
        enum ServerMessage {
            PushResponse {
                accepted: Vec<String>,
                rejected: Vec<RejectedOp>,
                server_clock: u64,
                #[serde(skip_serializing_if = "Option::is_none")]
                request_id: Option<String>,
            },
        }

        let msg = ServerMessage::PushResponse {
            accepted: vec!["op-1".to_string()],
            rejected: vec![RejectedOp {
                op_id: "op-2".to_string(),
                reason: "conflict".to_string(),
                winner: Some("op-existing".to_string()),
            }],
            server_clock: 42,
            request_id: Some("req-004".to_string()),
        };

        let json = serde_json::to_string(&msg).unwrap();

        assert!(json.contains(r#""type":"push_response""#));
        assert!(json.contains(r#""accepted":["op-1"]"#));
        assert!(json.contains(r#""server_clock":42"#));
        assert!(json.contains(r#""reason":"conflict""#));
    }
}
