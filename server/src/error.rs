//! Unified error handling for the server.

use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde::Serialize;

/// Application error type.
#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("Database error: {0}")]
    Database(#[from] sqlx::Error),

    #[error("Engine error: {0}")]
    Engine(#[from] carry_engine::Error),

    #[error("Invalid request: {0}")]
    BadRequest(String),

    #[error("Not found: {0}")]
    #[allow(dead_code)]
    NotFound(String),

    #[error("Unauthorized")]
    #[allow(dead_code)]
    Unauthorized,

    #[error("Internal error: {0}")]
    #[allow(dead_code)]
    Internal(String),
}

/// Error response body.
#[derive(Serialize)]
struct ErrorResponse {
    error: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    details: Option<String>,
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, error_message, details) = match &self {
            AppError::Database(e) => {
                tracing::error!("Database error: {:?}", e);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Database error".to_string(),
                    None,
                )
            }
            AppError::Engine(e) => {
                tracing::warn!("Engine error: {:?}", e);
                (StatusCode::BAD_REQUEST, e.to_string(), None)
            }
            AppError::BadRequest(msg) => (StatusCode::BAD_REQUEST, msg.clone(), None),
            AppError::NotFound(msg) => (StatusCode::NOT_FOUND, msg.clone(), None),
            AppError::Unauthorized => (StatusCode::UNAUTHORIZED, "Unauthorized".to_string(), None),
            AppError::Internal(msg) => {
                tracing::error!("Internal error: {}", msg);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Internal server error".to_string(),
                    Some(msg.clone()),
                )
            }
        };

        let body = Json(ErrorResponse {
            error: error_message,
            details,
        });

        (status, body).into_response()
    }
}

/// Result type alias for handlers.
pub type Result<T> = std::result::Result<T, AppError>;
