//! WebSocket connection manager.
//!
//! Tracks active WebSocket connections and provides broadcast capabilities
//! for pushing operations to connected clients.

use std::sync::Arc;

use dashmap::DashMap;
use tokio::sync::mpsc;

use super::ServerMessage;

/// Sender for WebSocket messages.
pub type MessageSender = mpsc::UnboundedSender<ServerMessage>;

/// A single WebSocket connection.
#[derive(Debug)]
pub struct Connection {
    /// Unique identifier for this connection
    pub id: String,
    /// Client's node ID
    pub node_id: String,
    /// Channel to send messages to this connection
    pub sender: MessageSender,
}

/// Manages active WebSocket connections.
///
/// Thread-safe and can be shared across handlers via `Arc`.
#[derive(Debug, Default)]
pub struct ConnectionManager {
    /// All active connections, keyed by connection ID.
    pub(crate) connections: DashMap<String, Connection>,
    /// Index of connections by node_id for efficient lookup.
    by_node_id: DashMap<String, Vec<String>>,
}

impl ConnectionManager {
    /// Create a new connection manager.
    pub fn new() -> Self {
        Self {
            connections: DashMap::new(),
            by_node_id: DashMap::new(),
        }
    }

    /// Create a new connection manager wrapped in Arc for sharing.
    pub fn new_shared() -> Arc<Self> {
        Arc::new(Self::new())
    }

    /// Register a new connection.
    ///
    /// Returns the connection ID.
    pub fn register(&self, node_id: String, sender: MessageSender) -> String {
        let conn_id = uuid::Uuid::new_v4().to_string();

        let connection = Connection {
            id: conn_id.clone(),
            node_id: node_id.clone(),
            sender,
        };

        // Add to main connections map
        self.connections.insert(conn_id.clone(), connection);

        // Add to node_id index
        self.by_node_id
            .entry(node_id)
            .or_default()
            .push(conn_id.clone());

        tracing::info!(conn_id = %conn_id, "WebSocket connection registered");

        conn_id
    }

    /// Unregister a connection.
    pub fn unregister(&self, conn_id: &str) {
        if let Some((_, conn)) = self.connections.remove(conn_id) {
            // Remove from node_id index
            if let Some(mut conn_ids) = self.by_node_id.get_mut(&conn.node_id) {
                conn_ids.retain(|id| id != conn_id);
                // Clean up empty entries
                if conn_ids.is_empty() {
                    drop(conn_ids);
                    self.by_node_id.remove(&conn.node_id);
                }
            }

            tracing::info!(conn_id = %conn_id, node_id = %conn.node_id, "WebSocket connection unregistered");
        }
    }

    /// Broadcast a message to all connections except the sender.
    ///
    /// Returns the number of connections that received the message.
    pub fn broadcast_except(&self, sender_conn_id: &str, message: ServerMessage) -> usize {
        let mut sent_count = 0;

        for entry in self.connections.iter() {
            let conn = entry.value();
            if conn.id != sender_conn_id {
                if conn.sender.send(message.clone()).is_ok() {
                    sent_count += 1;
                }
            }
        }

        tracing::debug!(
            sender = %sender_conn_id,
            recipients = sent_count,
            "Broadcast message to connections"
        );

        sent_count
    }

    /// Broadcast a message to all connections.
    ///
    /// Returns the number of connections that received the message.
    #[allow(dead_code)]
    pub fn broadcast_all(&self, message: ServerMessage) -> usize {
        let mut sent_count = 0;

        for entry in self.connections.iter() {
            if entry.value().sender.send(message.clone()).is_ok() {
                sent_count += 1;
            }
        }

        sent_count
    }

    /// Send a message to a specific connection.
    #[allow(dead_code)]
    pub fn send_to(&self, conn_id: &str, message: ServerMessage) -> bool {
        if let Some(conn) = self.connections.get(conn_id) {
            conn.sender.send(message).is_ok()
        } else {
            false
        }
    }

    /// Internal method to send a message to a connection (used by handler).
    pub(crate) fn send_to_internal(&self, conn_id: &str, message: ServerMessage) {
        if let Some(conn) = self.connections.get(conn_id) {
            let _ = conn.sender.send(message);
        }
    }

    /// Get the number of active connections.
    pub fn connection_count(&self) -> usize {
        self.connections.len()
    }

    /// Get the number of unique node IDs connected.
    #[allow(dead_code)]
    pub fn node_count(&self) -> usize {
        self.by_node_id.len()
    }
}

// Implement Clone for ServerMessage so we can broadcast
impl Clone for ServerMessage {
    fn clone(&self) -> Self {
        match self {
            ServerMessage::PullResponse {
                operations,
                sync_token,
                has_more,
                request_id,
            } => ServerMessage::PullResponse {
                operations: operations.clone(),
                sync_token: sync_token.clone(),
                has_more: *has_more,
                request_id: request_id.clone(),
            },
            ServerMessage::PushResponse {
                accepted,
                rejected,
                server_clock,
                request_id,
            } => ServerMessage::PushResponse {
                accepted: accepted.clone(),
                rejected: rejected.clone(),
                server_clock: *server_clock,
                request_id: request_id.clone(),
            },
            ServerMessage::OpsAvailable {
                operations,
                sync_token,
            } => ServerMessage::OpsAvailable {
                operations: operations.clone(),
                sync_token: sync_token.clone(),
            },
            ServerMessage::Pong => ServerMessage::Pong,
            ServerMessage::Error {
                message,
                request_id,
            } => ServerMessage::Error {
                message: message.clone(),
                request_id: request_id.clone(),
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_register_unregister() {
        let manager = ConnectionManager::new();
        let (tx, _rx) = mpsc::unbounded_channel();

        let conn_id = manager.register("node-1".to_string(), tx);
        assert_eq!(manager.connection_count(), 1);
        assert_eq!(manager.node_count(), 1);

        manager.unregister(&conn_id);
        assert_eq!(manager.connection_count(), 0);
        assert_eq!(manager.node_count(), 0);
    }

    #[test]
    fn test_broadcast_except() {
        let manager = ConnectionManager::new();

        let (tx1, mut rx1) = mpsc::unbounded_channel();
        let (tx2, mut rx2) = mpsc::unbounded_channel();

        let conn1 = manager.register("node-1".to_string(), tx1);
        let _conn2 = manager.register("node-2".to_string(), tx2);

        // Broadcast from conn1 should only reach conn2
        let sent = manager.broadcast_except(&conn1, ServerMessage::Pong);
        assert_eq!(sent, 1);

        // rx1 should not receive (sender excluded)
        assert!(rx1.try_recv().is_err());

        // rx2 should receive
        let msg = rx2.try_recv().unwrap();
        assert!(matches!(msg, ServerMessage::Pong));
    }
}
