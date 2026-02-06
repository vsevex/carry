//! Carry Server - Sync server for local-first data synchronization.
//!
//! This server provides HTTP and WebSocket endpoints for Flutter clients to sync their
//! local data with the server using the carry-engine reconciliation logic.

mod auth;
mod config;
mod db;
mod error;
mod handlers;
mod routes;
mod websocket;

use crate::config::Config;
use crate::db::Pool;
use crate::websocket::ConnectionManager;
use axum::Router;
use std::sync::Arc;
use tower_http::cors::{Any, CorsLayer};
use tower_http::trace::TraceLayer;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

/// Application state shared across handlers.
#[derive(Clone)]
pub struct AppState {
    pub pool: Pool,
    pub config: Arc<Config>,
    pub conn_manager: Arc<ConnectionManager>,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize tracing
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "carry_server=debug,tower_http=debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    // Load configuration
    dotenvy::dotenv().ok();
    let config = Config::from_env()?;

    tracing::info!("Starting Carry Server on {}:{}", config.host, config.port);

    // Create database pool
    let pool = db::create_pool(&config.database_url).await?;

    // Run migrations
    tracing::info!("Running database migrations...");
    db::run_migrations(&pool).await?;

    // Build application state
    let conn_manager = ConnectionManager::new_shared();
    let state = AppState {
        pool,
        config: Arc::new(config.clone()),
        conn_manager,
    };

    // Build router
    let app = Router::new()
        .merge(routes::create_routes())
        .layer(TraceLayer::new_for_http())
        .layer(
            CorsLayer::new()
                .allow_origin(Any)
                .allow_methods(Any)
                .allow_headers(Any),
        )
        .with_state(state);

    // Start server
    let addr = format!("{}:{}", config.host, config.port);
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    tracing::info!("Server listening on {}", addr);

    axum::serve(listener, app).await?;

    Ok(())
}
