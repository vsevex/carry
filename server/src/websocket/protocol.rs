//! WebSocket message protocol definitions.
//!
//! All messages are JSON-encoded and use snake_case for field names.

use carry_engine::Operation;
use serde::{Deserialize, Serialize};

use crate::handlers::RejectedOp;

/// Messages sent from client to server.
#[derive(Debug, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ClientMessage {
    /// Request operations since a sync token.
    Pull {
        /// Sync token from previous pull (null for initial sync)
        since: Option<String>,
        /// Maximum number of operations to return
        #[serde(default)]
        limit: Option<i64>,
        /// Request ID for correlating responses
        #[serde(default)]
        request_id: Option<String>,
    },

    /// Push operations to the server.
    Push {
        /// Client's node ID
        node_id: String,
        /// Operations to push
        operations: Vec<Operation>,
        /// Request ID for correlating responses
        #[serde(default)]
        request_id: Option<String>,
    },

    /// Keep-alive ping.
    Ping,
}

/// Messages sent from server to client.
#[derive(Debug, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ServerMessage {
    /// Response to a pull request.
    PullResponse {
        /// Operations since the sync token
        operations: Vec<Operation>,
        /// Token to use for next pull
        sync_token: String,
        /// Whether there are more operations to fetch
        has_more: bool,
        /// Request ID from the original request
        #[serde(skip_serializing_if = "Option::is_none")]
        request_id: Option<String>,
    },

    /// Response to a push request.
    PushResponse {
        /// Operation IDs that were accepted
        accepted: Vec<String>,
        /// Operations that were rejected (conflicts lost)
        rejected: Vec<RejectedOp>,
        /// Current server clock counter
        server_clock: u64,
        /// Request ID from the original request
        #[serde(skip_serializing_if = "Option::is_none")]
        request_id: Option<String>,
    },

    /// Push notification when new operations are available.
    /// Sent to all connected clients except the one that pushed.
    OpsAvailable {
        /// New operations that were pushed by another client
        operations: Vec<Operation>,
        /// Sync token representing the latest operation
        sync_token: String,
    },

    /// Response to ping.
    Pong,

    /// Error message.
    Error {
        /// Error description
        message: String,
        /// Request ID from the original request (if applicable)
        #[serde(skip_serializing_if = "Option::is_none")]
        request_id: Option<String>,
    },
}

impl ServerMessage {
    /// Create an error message.
    pub fn error(message: impl Into<String>, request_id: Option<String>) -> Self {
        ServerMessage::Error {
            message: message.into(),
            request_id,
        }
    }

    /// Create an ops_available push notification.
    pub fn ops_available(operations: Vec<Operation>, sync_token: String) -> Self {
        ServerMessage::OpsAvailable {
            operations,
            sync_token,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_client_message_deserialization() {
        let json = r#"{"type": "pull", "since": "123_abc", "limit": 50}"#;
        let msg: ClientMessage = serde_json::from_str(json).unwrap();
        match msg {
            ClientMessage::Pull { since, limit, .. } => {
                assert_eq!(since, Some("123_abc".to_string()));
                assert_eq!(limit, Some(50));
            }
            _ => panic!("Expected Pull message"),
        }

        let json = r#"{"type": "ping"}"#;
        let msg: ClientMessage = serde_json::from_str(json).unwrap();
        assert!(matches!(msg, ClientMessage::Ping));
    }

    #[test]
    fn test_server_message_serialization() {
        let msg = ServerMessage::Pong;
        let json = serde_json::to_string(&msg).unwrap();
        assert_eq!(json, r#"{"type":"pong"}"#);

        let msg = ServerMessage::error("test error", Some("req-1".to_string()));
        let json = serde_json::to_string(&msg).unwrap();
        assert!(json.contains(r#""type":"error""#));
        assert!(json.contains(r#""message":"test error""#));
        assert!(json.contains(r#""request_id":"req-1""#));
    }
}
