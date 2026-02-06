//! Push handler - processes incoming operations from clients.

use crate::db;
use crate::error::{AppError, Result};
use carry_engine::{
    CollectionSchema, FieldDef, FieldType, MergeStrategy, Operation, Reconciler, Schema,
};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;

/// Request body for push sync.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PushRequest {
    /// Client's node ID
    #[allow(dead_code)]
    pub node_id: String,
    /// Operations to push
    pub operations: Vec<Operation>,
}

/// Response for push sync.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PushResponse {
    /// Operation IDs that were accepted
    pub accepted: Vec<String>,
    /// Operations that were rejected (conflicts lost)
    pub rejected: Vec<RejectedOp>,
    /// Current server clock counter
    pub server_clock: u64,
}

/// A rejected operation with reason.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RejectedOp {
    pub op_id: String,
    pub reason: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub winner: Option<String>,
}

/// Process a push request from a client.
pub async fn handle_push(pool: &PgPool, request: PushRequest) -> Result<PushResponse> {
    if request.operations.is_empty() {
        let server_clock = db::get_server_clock(pool).await?;
        return Ok(PushResponse {
            accepted: vec![],
            rejected: vec![],
            server_clock,
        });
    }

    // Get the default schema (in a real app, this would be loaded from config)
    let schema = get_default_schema();

    let mut accepted = Vec::new();
    let mut rejected = Vec::new();

    for op in &request.operations {
        // Check if operation already exists (idempotency)
        if db::operation_exists(pool, op.op_id()).await? {
            // Already processed, treat as accepted
            accepted.push(op.op_id().clone());
            continue;
        }

        // Get existing record if any
        let existing_record = db::get_record(pool, op.collection(), op.record_id()).await?;

        // Check for conflicts
        if let Some(stored) = existing_record {
            let existing = stored.to_record();

            // Use reconciler to determine if this operation wins
            let mut reconciler = Reconciler::new(&schema, MergeStrategy::ClockWins);

            // Load existing record state
            let existing_op = create_synthetic_op(&existing);
            reconciler.load_records(std::iter::once((
                existing.clone(),
                existing_op.clone(),
                carry_engine::OpSource::Remote,
            )));

            // Run reconciliation with the incoming operation
            let (result, final_records) = reconciler.reconcile(vec![op.clone()], vec![]);

            // Check if incoming op was accepted or rejected
            if result.accepted_local.contains(op.op_id()) {
                // Operation wins - store it
                if let Err(e) = db::insert_operation(pool, op).await {
                    // Handle unique constraint violation (race condition)
                    if is_unique_violation(&e) {
                        accepted.push(op.op_id().clone());
                        continue;
                    }
                    return Err(e.into());
                }

                // Update record state
                let key = (op.collection().clone(), op.record_id().clone());
                if let Some(record) = final_records.get(&key) {
                    db::upsert_record(pool, record).await?;
                }

                accepted.push(op.op_id().clone());
            } else {
                // Operation loses to existing
                rejected.push(RejectedOp {
                    op_id: op.op_id().clone(),
                    reason: "conflict".to_string(),
                    winner: Some(existing_op.op_id().clone()),
                });
            }
        } else {
            // No conflict - just insert
            if let Err(e) = db::insert_operation(pool, op).await {
                if is_unique_violation(&e) {
                    accepted.push(op.op_id().clone());
                    continue;
                }
                return Err(e.into());
            }

            // Create/update record state
            let record = operation_to_record(op)?;
            db::upsert_record(pool, &record).await?;

            accepted.push(op.op_id().clone());
        }
    }

    let server_clock = db::get_server_clock(pool).await?;

    Ok(PushResponse {
        accepted,
        rejected,
        server_clock,
    })
}

/// Create a synthetic operation representing current record state.
fn create_synthetic_op(record: &carry_engine::Record) -> Operation {
    Operation::Create(carry_engine::CreateOp::new(
        format!("__existing__{}", record.id),
        record.id.clone(),
        record.collection.clone(),
        record.payload.clone(),
        record.metadata.created_at,
        record.metadata.clock.clone(),
    ))
}

/// Convert an operation to a record (for create operations).
fn operation_to_record(op: &Operation) -> Result<carry_engine::Record> {
    match op {
        Operation::Create(create_op) => Ok(carry_engine::Record::new(
            create_op.id.clone(),
            create_op.collection.clone(),
            create_op.payload.clone(),
            create_op.timestamp,
            create_op.clock.clone(),
        )),
        Operation::Update(_update_op) => {
            // For updates, we need the existing record - this shouldn't be called
            // for new records
            Err(AppError::BadRequest(
                "Cannot create record from update operation".to_string(),
            ))
        }
        Operation::Delete(_) => Err(AppError::BadRequest(
            "Cannot create record from delete operation".to_string(),
        )),
    }
}

/// Check if a SQL error is a unique constraint violation.
fn is_unique_violation(e: &sqlx::Error) -> bool {
    if let sqlx::Error::Database(db_err) = e {
        // PostgreSQL unique violation code is "23505"
        db_err.code().map(|c| c == "23505").unwrap_or(false)
    } else {
        false
    }
}

/// Get the default schema.
/// In a real application, this would be loaded from configuration or database.
fn get_default_schema() -> Schema {
    // Permissive schema that accepts any collection with JSON payload
    let mut schema = Schema::new(1);

    // Add some common collections
    // In production, this would be dynamically configured
    schema = schema.with_collection(CollectionSchema::new(
        "users",
        vec![
            FieldDef::optional("name", FieldType::String),
            FieldDef::optional("email", FieldType::String),
            FieldDef::optional("age", FieldType::Int),
        ],
    ));

    schema = schema.with_collection(CollectionSchema::new(
        "posts",
        vec![
            FieldDef::optional("title", FieldType::String),
            FieldDef::optional("body", FieldType::String),
            FieldDef::optional("createdAt", FieldType::Timestamp),
        ],
    ));

    schema = schema.with_collection(CollectionSchema::new(
        "todos",
        vec![
            FieldDef::optional("title", FieldType::String),
            FieldDef::optional("completed", FieldType::Bool),
            FieldDef::optional("createdAt", FieldType::Timestamp),
        ],
    ));

    schema
}
