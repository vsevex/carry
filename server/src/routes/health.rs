//! Health check endpoint.

use axum::{routing::get, Json, Router};
use serde::Serialize;

use crate::AppState;

/// Health check response.
#[derive(Serialize)]
pub struct HealthResponse {
    pub status: String,
    pub version: String,
}

/// Create health routes.
pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/health", get(health_check))
        .route("/", get(root))
}

/// Health check handler.
async fn health_check() -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "ok".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
    })
}

/// Root handler.
async fn root() -> &'static str {
    "Carry Sync Server"
}
