//! Pull handler - serves operations to clients for sync.

use crate::db;
use crate::error::Result;
use carry_engine::Operation;
use serde::{Deserialize, Serialize};
use sqlx::PgPool;

/// Query parameters for pull sync.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PullQuery {
    /// Sync token from previous pull (empty for initial sync)
    pub since: Option<String>,
    /// Maximum number of operations to return
    pub limit: Option<i64>,
}

/// Response for pull sync.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PullResponse {
    /// Operations since the sync token
    pub operations: Vec<Operation>,
    /// Token to use for next pull
    pub sync_token: String,
    /// Whether there are more operations to fetch
    pub has_more: bool,
}

/// Default limit for pull operations.
const DEFAULT_LIMIT: i64 = 100;

/// Maximum limit for pull operations.
const MAX_LIMIT: i64 = 1000;

/// Process a pull request from a client.
pub async fn handle_pull(pool: &PgPool, query: PullQuery) -> Result<PullResponse> {
    let limit = query
        .limit
        .map(|l| l.clamp(1, MAX_LIMIT))
        .unwrap_or(DEFAULT_LIMIT);

    // Fetch one more than requested to check if there are more
    let stored_ops = db::get_operations_since(pool, query.since.as_deref(), limit + 1).await?;

    let has_more = stored_ops.len() as i64 > limit;
    let ops_to_return: Vec<_> = stored_ops.into_iter().take(limit as usize).collect();

    // Convert to engine operations
    let mut operations = Vec::with_capacity(ops_to_return.len());
    for stored in &ops_to_return {
        match stored.to_operation() {
            Ok(op) => operations.push(op),
            Err(e) => {
                tracing::warn!("Failed to convert stored operation {}: {}", stored.op_id, e);
                // Skip invalid operations
            }
        }
    }

    // Generate sync token from last operation
    let sync_token = if let Some(last) = ops_to_return.last() {
        format!("{}_{}", last.timestamp, last.op_id)
    } else {
        query.since.unwrap_or_default()
    };

    Ok(PullResponse {
        operations,
        sync_token,
        has_more,
    })
}
