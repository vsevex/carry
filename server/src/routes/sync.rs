//! Sync endpoint routes.

use axum::{
    extract::{
        ws::{WebSocket, WebSocketUpgrade},
        Query, State,
    },
    http::HeaderMap,
    response::IntoResponse,
    routing::get,
    Json, Router,
};
use std::sync::Arc;

use crate::auth::AuthUser;
use crate::error::Result;
use crate::handlers::{
    handle_pull, handle_push, handle_websocket_connection, PullQuery, PullResponse, PushRequest,
    PushResponse,
};
use crate::AppState;

/// Create sync routes.
pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/sync", get(pull_handler).post(push_handler))
        .route("/sync/ws", get(websocket_handler))
}

/// POST /sync - Push operations to server.
async fn push_handler(
    State(state): State<AppState>,
    _auth: AuthUser,
    Json(request): Json<PushRequest>,
) -> Result<Json<PushResponse>> {
    let response = handle_push(&state.pool, request).await?;
    Ok(Json(response))
}

/// GET /sync - Pull operations from server.
async fn pull_handler(
    State(state): State<AppState>,
    _auth: AuthUser,
    Query(query): Query<PullQuery>,
) -> Result<Json<PullResponse>> {
    let response = handle_pull(&state.pool, query).await?;
    Ok(Json(response))
}

/// GET /sync/ws - WebSocket endpoint for real-time sync.
///
/// Clients should connect with:
/// - `Authorization: Bearer <token>` header (if auth is required)
/// - `X-Node-Id: <node_id>` header to identify the client
async fn websocket_handler(
    State(state): State<AppState>,
    headers: HeaderMap,
    ws: WebSocketUpgrade,
) -> impl IntoResponse {
    // Extract node_id from header (required for WebSocket)
    let node_id = headers
        .get("x-node-id")
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string())
        .unwrap_or_else(|| uuid::Uuid::new_v4().to_string());

    // Validate auth if configured
    // Note: For WebSocket, we do auth validation before upgrade
    if let Some(ref _secret) = state.config.auth_secret {
        // Check Authorization header
        let auth_header = headers.get("authorization").and_then(|v| v.to_str().ok());

        match auth_header {
            Some(header) if header.starts_with("Bearer ") => {
                let token = header.trim_start_matches("Bearer ");
                if token.is_empty() {
                    return ws.on_upgrade(|socket| async {
                        // Send error and close
                        let _ = socket;
                        tracing::warn!("WebSocket connection rejected: empty bearer token");
                    });
                }
                // TODO: Validate token properly
            }
            Some(_) => {
                return ws.on_upgrade(|socket| async {
                    let _ = socket;
                    tracing::warn!("WebSocket connection rejected: invalid auth header format");
                });
            }
            None => {
                return ws.on_upgrade(|socket| async {
                    let _ = socket;
                    tracing::warn!("WebSocket connection rejected: missing auth header");
                });
            }
        }
    }

    let pool = Arc::new(state.pool.clone());
    let conn_manager = state.conn_manager.clone();

    tracing::info!(node_id = %node_id, "WebSocket upgrade requested");

    ws.on_upgrade(move |socket: WebSocket| {
        handle_websocket_connection(socket, pool, conn_manager, node_id)
    })
}
