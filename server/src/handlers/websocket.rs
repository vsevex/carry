//! WebSocket handler for real-time sync.
//!
//! Handles WebSocket connections and dispatches messages to the appropriate
//! sync handlers (pull/push) while managing real-time notifications.

use std::sync::Arc;

use axum::extract::ws::{Message, WebSocket};
use futures::{SinkExt, StreamExt};
use sqlx::PgPool;
use tokio::sync::mpsc;

use crate::websocket::{ClientMessage, ConnectionManager, ServerMessage};

use super::{handle_pull, handle_push, PullQuery, PushRequest};

/// Handle an established WebSocket connection.
///
/// This function:
/// 1. Registers the connection with the manager
/// 2. Spawns a task to forward outgoing messages
/// 3. Processes incoming messages in a loop
/// 4. Cleans up on disconnect
pub async fn handle_websocket_connection(
    socket: WebSocket,
    pool: Arc<PgPool>,
    conn_manager: Arc<ConnectionManager>,
    node_id: String,
) {
    // Split the socket into sender and receiver
    let (mut ws_sender, mut ws_receiver) = socket.split();

    // Create channel for sending messages to this connection
    let (tx, mut rx) = mpsc::unbounded_channel::<ServerMessage>();

    // Register with connection manager
    let conn_id = conn_manager.register(node_id.clone(), tx);

    tracing::info!(
        conn_id = %conn_id,
        node_id = %node_id,
        "WebSocket client connected"
    );

    // Spawn task to forward messages from channel to WebSocket
    let send_task = tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            match serde_json::to_string(&msg) {
                Ok(text) => {
                    if let Err(e) = ws_sender.send(Message::Text(text.into())).await {
                        tracing::warn!("Failed to send WebSocket message: {}", e);
                        break;
                    }
                }
                Err(e) => {
                    tracing::error!("Failed to serialize WebSocket message: {}", e);
                }
            }
        }
    });

    // Process incoming messages
    while let Some(result) = ws_receiver.next().await {
        match result {
            Ok(Message::Text(text)) => {
                let response =
                    process_message(&text, &pool, &conn_manager, &conn_id, &node_id).await;

                // Send response via the connection manager channel
                conn_manager.send_to_internal(&conn_id, response);
            }
            Ok(Message::Binary(_)) => {
                tracing::warn!("Binary messages not supported");
            }
            Ok(Message::Ping(data)) => {
                // Axum handles pong automatically, but we could log it
                tracing::trace!("Received ping: {} bytes", data.len());
            }
            Ok(Message::Pong(_)) => {
                tracing::trace!("Received pong");
            }
            Ok(Message::Close(_)) => {
                tracing::info!(conn_id = %conn_id, "WebSocket close frame received");
                break;
            }
            Err(e) => {
                tracing::warn!(conn_id = %conn_id, "WebSocket error: {}", e);
                break;
            }
        }
    }

    // Clean up
    conn_manager.unregister(&conn_id);
    send_task.abort();

    tracing::info!(
        conn_id = %conn_id,
        node_id = %node_id,
        active_connections = conn_manager.connection_count(),
        "WebSocket client disconnected"
    );
}

/// Process a client message and return a server response.
async fn process_message(
    text: &str,
    pool: &PgPool,
    conn_manager: &ConnectionManager,
    conn_id: &str,
    node_id: &str,
) -> ServerMessage {
    // Parse the message
    let client_msg: ClientMessage = match serde_json::from_str(text) {
        Ok(msg) => msg,
        Err(e) => {
            return ServerMessage::error(format!("Invalid message format: {}", e), None);
        }
    };

    match client_msg {
        ClientMessage::Pull {
            since,
            limit,
            request_id,
        } => {
            let query = PullQuery { since, limit };

            match handle_pull(pool, query).await {
                Ok(response) => ServerMessage::PullResponse {
                    operations: response.operations,
                    sync_token: response.sync_token,
                    has_more: response.has_more,
                    request_id,
                },
                Err(e) => ServerMessage::error(e.to_string(), request_id),
            }
        }

        ClientMessage::Push {
            node_id: push_node_id,
            operations,
            request_id,
        } => {
            // Verify node_id matches (optional security check)
            if push_node_id != node_id {
                tracing::warn!(
                    expected = %node_id,
                    received = %push_node_id,
                    "Node ID mismatch in push request"
                );
            }

            let request = PushRequest {
                node_id: push_node_id,
                operations: operations.clone(),
            };

            match handle_push(pool, request).await {
                Ok(response) => {
                    // Broadcast accepted operations to other clients
                    if !response.accepted.is_empty() {
                        // Filter to only accepted operations for broadcast
                        let accepted_ops: Vec<_> = operations
                            .into_iter()
                            .filter(|op| response.accepted.contains(op.op_id()))
                            .collect();

                        if !accepted_ops.is_empty() {
                            // Generate sync token for the broadcast
                            let sync_token = if let Some(last_op) = accepted_ops.last() {
                                format!(
                                    "{}_{}",
                                    chrono::Utc::now().timestamp_millis(),
                                    last_op.op_id()
                                )
                            } else {
                                String::new()
                            };

                            let broadcast_msg =
                                ServerMessage::ops_available(accepted_ops, sync_token);
                            let sent = conn_manager.broadcast_except(conn_id, broadcast_msg);
                            tracing::debug!(
                                sent_to = sent,
                                accepted = response.accepted.len(),
                                "Broadcast operations to connected clients"
                            );
                        }
                    }

                    ServerMessage::PushResponse {
                        accepted: response.accepted,
                        rejected: response
                            .rejected
                            .into_iter()
                            .map(|r| crate::handlers::RejectedOp {
                                op_id: r.op_id,
                                reason: r.reason,
                                winner: r.winner,
                            })
                            .collect(),
                        server_clock: response.server_clock,
                        request_id,
                    }
                }
                Err(e) => ServerMessage::error(e.to_string(), request_id),
            }
        }

        ClientMessage::Ping => ServerMessage::Pong,
    }
}
