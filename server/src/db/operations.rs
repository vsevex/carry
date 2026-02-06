//! Database operations for the operations table.

use carry_engine::{CreateOp, DeleteOp, LogicalClock, Operation, UpdateOp};
use sqlx::{PgPool, Row};

/// A stored operation row from the database.
#[derive(Debug)]
pub struct StoredOperation {
    #[allow(dead_code)]
    pub id: i32,
    pub op_id: String,
    #[allow(dead_code)]
    pub node_id: String,
    pub collection: String,
    pub record_id: String,
    pub op_type: String,
    pub payload: Option<serde_json::Value>,
    pub clock_counter: i64,
    pub clock_node_id: String,
    pub timestamp: i64,
    pub base_version: Option<i64>,
    #[allow(dead_code)]
    pub created_at: chrono::DateTime<chrono::Utc>,
}

impl<'r> sqlx::FromRow<'r, sqlx::postgres::PgRow> for StoredOperation {
    fn from_row(row: &'r sqlx::postgres::PgRow) -> Result<Self, sqlx::Error> {
        Ok(StoredOperation {
            id: row.try_get("id")?,
            op_id: row.try_get("op_id")?,
            node_id: row.try_get("node_id")?,
            collection: row.try_get("collection")?,
            record_id: row.try_get("record_id")?,
            op_type: row.try_get("op_type")?,
            payload: row.try_get("payload")?,
            clock_counter: row.try_get("clock_counter")?,
            clock_node_id: row.try_get("clock_node_id")?,
            timestamp: row.try_get("timestamp")?,
            base_version: row.try_get("base_version")?,
            created_at: row.try_get("created_at")?,
        })
    }
}

impl StoredOperation {
    /// Convert database row to carry-engine Operation.
    pub fn to_operation(&self) -> Result<Operation, String> {
        let clock = LogicalClock::with_counter(&self.clock_node_id, self.clock_counter as u64);

        match self.op_type.as_str() {
            "create" => {
                let payload = self.payload.clone().unwrap_or(serde_json::Value::Null);
                Ok(Operation::Create(CreateOp::new(
                    &self.op_id,
                    &self.record_id,
                    &self.collection,
                    payload,
                    self.timestamp as u64,
                    clock,
                )))
            }
            "update" => {
                let payload = self.payload.clone().unwrap_or(serde_json::Value::Null);
                let base_version = self.base_version.unwrap_or(0) as u64;
                Ok(Operation::Update(UpdateOp::new(
                    &self.op_id,
                    &self.record_id,
                    &self.collection,
                    payload,
                    base_version,
                    self.timestamp as u64,
                    clock,
                )))
            }
            "delete" => {
                let base_version = self.base_version.unwrap_or(0) as u64;
                Ok(Operation::Delete(DeleteOp::new(
                    &self.op_id,
                    &self.record_id,
                    &self.collection,
                    base_version,
                    self.timestamp as u64,
                    clock,
                )))
            }
            other => Err(format!("Unknown operation type: {}", other)),
        }
    }
}

/// Insert an operation into the database.
pub async fn insert_operation(pool: &PgPool, op: &Operation) -> Result<i32, sqlx::Error> {
    let (op_type, payload, base_version) = match op {
        Operation::Create(c) => ("create", Some(&c.payload), None),
        Operation::Update(u) => ("update", Some(&u.payload), Some(u.base_version as i64)),
        Operation::Delete(d) => ("delete", None, Some(d.base_version as i64)),
    };

    let clock = op.clock();

    let result: (i32,) = sqlx::query_as(
        r#"
        INSERT INTO operations (
            op_id, node_id, collection, record_id, op_type,
            payload, clock_counter, clock_node_id, timestamp, base_version
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
        RETURNING id
        "#,
    )
    .bind(op.op_id())
    .bind(&clock.node_id)
    .bind(op.collection())
    .bind(op.record_id())
    .bind(op_type)
    .bind(payload)
    .bind(clock.counter as i64)
    .bind(&clock.node_id)
    .bind(op.timestamp() as i64)
    .bind(base_version)
    .fetch_one(pool)
    .await?;

    Ok(result.0)
}

/// Get operations since a given sync token.
///
/// The sync token format is "{timestamp}_{op_id}" or empty for the first sync.
pub async fn get_operations_since(
    pool: &PgPool,
    since_token: Option<&str>,
    limit: i64,
) -> Result<Vec<StoredOperation>, sqlx::Error> {
    match since_token {
        Some(token) if !token.is_empty() => {
            // Parse token: "timestamp_opId"
            let parts: Vec<&str> = token.splitn(2, '_').collect();
            if parts.len() != 2 {
                // Invalid token, return from beginning
                return get_all_operations(pool, limit).await;
            }

            let since_timestamp: i64 = parts[0].parse().unwrap_or(0);
            let since_op_id = parts[1];

            sqlx::query_as::<_, StoredOperation>(
                r#"
                SELECT id, op_id, node_id, collection, record_id, op_type,
                       payload, clock_counter, clock_node_id, timestamp,
                       base_version, created_at
                FROM operations
                WHERE (timestamp, op_id) > ($1, $2)
                ORDER BY timestamp ASC, op_id ASC
                LIMIT $3
                "#,
            )
            .bind(since_timestamp)
            .bind(since_op_id)
            .bind(limit)
            .fetch_all(pool)
            .await
        }
        _ => get_all_operations(pool, limit).await,
    }
}

/// Get all operations (for initial sync).
async fn get_all_operations(
    pool: &PgPool,
    limit: i64,
) -> Result<Vec<StoredOperation>, sqlx::Error> {
    sqlx::query_as::<_, StoredOperation>(
        r#"
        SELECT id, op_id, node_id, collection, record_id, op_type,
               payload, clock_counter, clock_node_id, timestamp,
               base_version, created_at
        FROM operations
        ORDER BY timestamp ASC, op_id ASC
        LIMIT $1
        "#,
    )
    .bind(limit)
    .fetch_all(pool)
    .await
}

/// Check if an operation with the given op_id already exists.
pub async fn operation_exists(pool: &PgPool, op_id: &str) -> Result<bool, sqlx::Error> {
    let result: (bool,) =
        sqlx::query_as(r#"SELECT EXISTS(SELECT 1 FROM operations WHERE op_id = $1)"#)
            .bind(op_id)
            .fetch_one(pool)
            .await?;

    Ok(result.0)
}

/// Get the latest server clock counter.
pub async fn get_server_clock(pool: &PgPool) -> Result<u64, sqlx::Error> {
    let result: (i64,) =
        sqlx::query_as(r#"SELECT COALESCE(MAX(clock_counter), 0) FROM operations"#)
            .fetch_one(pool)
            .await?;

    Ok(result.0 as u64)
}
