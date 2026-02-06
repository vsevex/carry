//! Configuration management for the server.

use std::env;

/// Server configuration loaded from environment variables.
#[derive(Debug, Clone)]
pub struct Config {
    /// Server host address
    pub host: String,
    /// Server port
    pub port: u16,
    /// PostgreSQL connection URL
    pub database_url: String,
    /// Secret key for token validation (placeholder for auth)
    pub auth_secret: Option<String>,
}

impl Config {
    /// Load configuration from environment variables.
    pub fn from_env() -> Result<Self, ConfigError> {
        let host = env::var("HOST").unwrap_or_else(|_| "0.0.0.0".to_string());

        let port = env::var("PORT")
            .unwrap_or_else(|_| "3000".to_string())
            .parse()
            .map_err(|_| ConfigError::InvalidPort)?;

        let database_url = env::var("DATABASE_URL").map_err(|_| ConfigError::MissingDatabaseUrl)?;

        let auth_secret = env::var("AUTH_SECRET").ok();

        Ok(Self {
            host,
            port,
            database_url,
            auth_secret,
        })
    }
}

/// Configuration errors.
#[derive(Debug, thiserror::Error)]
pub enum ConfigError {
    #[error("DATABASE_URL environment variable is required")]
    MissingDatabaseUrl,

    #[error("Invalid PORT value")]
    InvalidPort,
}
