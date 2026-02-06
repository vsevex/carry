//! HTTP route definitions.

mod health;
mod sync;

use crate::AppState;
use axum::Router;

/// Create all application routes.
pub fn create_routes() -> Router<AppState> {
    Router::new().merge(health::routes()).merge(sync::routes())
}
