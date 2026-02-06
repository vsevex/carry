//! Database connection pool management.

use sqlx::postgres::PgPoolOptions;
use sqlx::PgPool;

/// Type alias for the database pool.
pub type Pool = PgPool;

/// Create a new database connection pool.
pub async fn create_pool(database_url: &str) -> Result<Pool, sqlx::Error> {
    PgPoolOptions::new()
        .max_connections(10)
        .connect(database_url)
        .await
}

/// Run database migrations.
pub async fn run_migrations(pool: &Pool) -> Result<(), sqlx::migrate::MigrateError> {
    sqlx::migrate!("./migrations").run(pool).await
}
