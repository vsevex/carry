//! Sync endpoint routes.

use axum::{
    extract::{Query, State},
    routing::get,
    Json, Router,
};

use crate::auth::AuthUser;
use crate::error::Result;
use crate::handlers::{
    handle_pull, handle_push, PullQuery, PullResponse, PushRequest, PushResponse,
};
use crate::AppState;

/// Create sync routes.
pub fn routes() -> Router<AppState> {
    Router::new().route("/sync", get(pull_handler).post(push_handler))
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
