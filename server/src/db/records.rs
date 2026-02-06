//! Database operations for the records table.

use carry_engine::{LogicalClock, Metadata, Origin, Record};
use sqlx::{PgPool, Row};

/// A stored record row from the database.
#[derive(Debug)]
pub struct StoredRecord {
    pub collection: String,
    pub record_id: String,
    pub version: i64,
    pub payload: serde_json::Value,
    pub deleted: bool,
    pub clock_counter: i64,
    pub clock_node_id: String,
    pub created_at: i64,
    pub updated_at: i64,
}

impl<'r> sqlx::FromRow<'r, sqlx::postgres::PgRow> for StoredRecord {
    fn from_row(row: &'r sqlx::postgres::PgRow) -> Result<Self, sqlx::Error> {
        Ok(StoredRecord {
            collection: row.try_get("collection")?,
            record_id: row.try_get("record_id")?,
            version: row.try_get("version")?,
            payload: row.try_get("payload")?,
            deleted: row.try_get("deleted")?,
            clock_counter: row.try_get("clock_counter")?,
            clock_node_id: row.try_get("clock_node_id")?,
            created_at: row.try_get("created_at")?,
            updated_at: row.try_get("updated_at")?,
        })
    }
}

impl StoredRecord {
    /// Convert database row to carry-engine Record.
    pub fn to_record(&self) -> Record {
        Record {
            id: self.record_id.clone(),
            collection: self.collection.clone(),
            version: self.version as u64,
            payload: self.payload.clone(),
            metadata: Metadata {
                created_at: self.created_at as u64,
                updated_at: self.updated_at as u64,
                origin: Origin::Remote,
                clock: LogicalClock::with_counter(&self.clock_node_id, self.clock_counter as u64),
            },
            deleted: self.deleted,
        }
    }
}

/// Upsert a record (insert or update).
pub async fn upsert_record(pool: &PgPool, record: &Record) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        INSERT INTO records (
            collection, record_id, version, payload, deleted,
            clock_counter, clock_node_id, created_at, updated_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        ON CONFLICT (collection, record_id) DO UPDATE SET
            version = EXCLUDED.version,
            payload = EXCLUDED.payload,
            deleted = EXCLUDED.deleted,
            clock_counter = EXCLUDED.clock_counter,
            clock_node_id = EXCLUDED.clock_node_id,
            updated_at = EXCLUDED.updated_at
        "#,
    )
    .bind(&record.collection)
    .bind(&record.id)
    .bind(record.version as i64)
    .bind(&record.payload)
    .bind(record.deleted)
    .bind(record.metadata.clock.counter as i64)
    .bind(&record.metadata.clock.node_id)
    .bind(record.metadata.created_at as i64)
    .bind(record.metadata.updated_at as i64)
    .execute(pool)
    .await?;

    Ok(())
}

/// Get a record by collection and ID.
pub async fn get_record(
    pool: &PgPool,
    collection: &str,
    record_id: &str,
) -> Result<Option<StoredRecord>, sqlx::Error> {
    sqlx::query_as::<_, StoredRecord>(
        r#"
        SELECT collection, record_id, version, payload, deleted,
               clock_counter, clock_node_id, created_at, updated_at
        FROM records
        WHERE collection = $1 AND record_id = $2
        "#,
    )
    .bind(collection)
    .bind(record_id)
    .fetch_optional(pool)
    .await
}

/// Get all records in a collection.
#[allow(dead_code)]
pub async fn get_records_in_collection(
    pool: &PgPool,
    collection: &str,
) -> Result<Vec<StoredRecord>, sqlx::Error> {
    sqlx::query_as::<_, StoredRecord>(
        r#"
        SELECT collection, record_id, version, payload, deleted,
               clock_counter, clock_node_id, created_at, updated_at
        FROM records
        WHERE collection = $1
        "#,
    )
    .bind(collection)
    .fetch_all(pool)
    .await
}

/// Get all active (non-deleted) records.
#[allow(dead_code)]
pub async fn get_all_active_records(pool: &PgPool) -> Result<Vec<StoredRecord>, sqlx::Error> {
    sqlx::query_as::<_, StoredRecord>(
        r#"
        SELECT collection, record_id, version, payload, deleted,
               clock_counter, clock_node_id, created_at, updated_at
        FROM records
        WHERE deleted = false
        "#,
    )
    .fetch_all(pool)
    .await
}
