//! Operation types for expressing changes.
//!
//! Changes are expressed as operations, not direct mutations.
//! This enables offline-first behavior with operation logging and reconciliation.

use crate::{CollectionName, LogicalClock, RecordId, Timestamp, Version};
use serde::{Deserialize, Serialize};

/// Unique identifier for an operation.
pub type OperationId = String;

/// A create operation.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateOp {
    /// Operation ID
    pub op_id: OperationId,
    /// Record ID to create
    pub id: RecordId,
    /// Target collection
    pub collection: CollectionName,
    /// Initial payload
    pub payload: serde_json::Value,
    /// Timestamp of operation
    pub timestamp: Timestamp,
    /// Logical clock at operation time
    pub clock: LogicalClock,
}

/// An update operation.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateOp {
    /// Operation ID
    pub op_id: OperationId,
    /// Record ID to update
    pub id: RecordId,
    /// Target collection
    pub collection: CollectionName,
    /// New payload (full replacement in v1)
    pub payload: serde_json::Value,
    /// Version this update is based on
    pub base_version: Version,
    /// Timestamp of operation
    pub timestamp: Timestamp,
    /// Logical clock at operation time
    pub clock: LogicalClock,
}

/// A delete operation.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DeleteOp {
    /// Operation ID
    pub op_id: OperationId,
    /// Record ID to delete
    pub id: RecordId,
    /// Target collection
    pub collection: CollectionName,
    /// Version this delete is based on
    pub base_version: Version,
    /// Timestamp of operation
    pub timestamp: Timestamp,
    /// Logical clock at operation time
    pub clock: LogicalClock,
}

/// An operation that can be applied to the store.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "lowercase")]
pub enum Operation {
    Create(CreateOp),
    Update(UpdateOp),
    Delete(DeleteOp),
}

impl Operation {
    /// Get the operation ID.
    pub fn op_id(&self) -> &OperationId {
        match self {
            Operation::Create(op) => &op.op_id,
            Operation::Update(op) => &op.op_id,
            Operation::Delete(op) => &op.op_id,
        }
    }

    /// Get the record ID this operation targets.
    pub fn record_id(&self) -> &RecordId {
        match self {
            Operation::Create(op) => &op.id,
            Operation::Update(op) => &op.id,
            Operation::Delete(op) => &op.id,
        }
    }

    /// Get the collection this operation targets.
    pub fn collection(&self) -> &CollectionName {
        match self {
            Operation::Create(op) => &op.collection,
            Operation::Update(op) => &op.collection,
            Operation::Delete(op) => &op.collection,
        }
    }

    /// Get the logical clock of this operation.
    pub fn clock(&self) -> &LogicalClock {
        match self {
            Operation::Create(op) => &op.clock,
            Operation::Update(op) => &op.clock,
            Operation::Delete(op) => &op.clock,
        }
    }

    /// Get the timestamp of this operation.
    pub fn timestamp(&self) -> Timestamp {
        match self {
            Operation::Create(op) => op.timestamp,
            Operation::Update(op) => op.timestamp,
            Operation::Delete(op) => op.timestamp,
        }
    }
}

impl CreateOp {
    /// Create a new create operation.
    pub fn new(
        op_id: impl Into<OperationId>,
        id: impl Into<RecordId>,
        collection: impl Into<CollectionName>,
        payload: serde_json::Value,
        timestamp: Timestamp,
        clock: LogicalClock,
    ) -> Self {
        Self {
            op_id: op_id.into(),
            id: id.into(),
            collection: collection.into(),
            payload,
            timestamp,
            clock,
        }
    }
}

impl UpdateOp {
    /// Create a new update operation.
    pub fn new(
        op_id: impl Into<OperationId>,
        id: impl Into<RecordId>,
        collection: impl Into<CollectionName>,
        payload: serde_json::Value,
        base_version: Version,
        timestamp: Timestamp,
        clock: LogicalClock,
    ) -> Self {
        Self {
            op_id: op_id.into(),
            id: id.into(),
            collection: collection.into(),
            payload,
            base_version,
            timestamp,
            clock,
        }
    }
}

impl DeleteOp {
    /// Create a new delete operation.
    pub fn new(
        op_id: impl Into<OperationId>,
        id: impl Into<RecordId>,
        collection: impl Into<CollectionName>,
        base_version: Version,
        timestamp: Timestamp,
        clock: LogicalClock,
    ) -> Self {
        Self {
            op_id: op_id.into(),
            id: id.into(),
            collection: collection.into(),
            base_version,
            timestamp,
            clock,
        }
    }
}

/// Ordering for operations used in reconciliation.
/// Operations are ordered by: (clock, timestamp, op_id)
impl Ord for Operation {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        match self.clock().cmp(other.clock()) {
            std::cmp::Ordering::Equal => match self.timestamp().cmp(&other.timestamp()) {
                std::cmp::Ordering::Equal => self.op_id().cmp(other.op_id()),
                other => other,
            },
            other => other,
        }
    }
}

impl PartialOrd for Operation {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

impl Eq for Operation {}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn create_op() {
        let clock = LogicalClock::with_counter("node-1", 1);
        let op = CreateOp::new(
            "op-1",
            "user-1",
            "users",
            json!({"name": "Alice"}),
            1000,
            clock,
        );

        assert_eq!(op.op_id, "op-1");
        assert_eq!(op.id, "user-1");
        assert_eq!(op.collection, "users");
    }

    #[test]
    fn update_op() {
        let clock = LogicalClock::with_counter("node-1", 2);
        let op = UpdateOp::new(
            "op-2",
            "user-1",
            "users",
            json!({"name": "Alice Smith"}),
            1,
            2000,
            clock,
        );

        assert_eq!(op.base_version, 1);
    }

    #[test]
    fn delete_op() {
        let clock = LogicalClock::with_counter("node-1", 3);
        let op = DeleteOp::new("op-3", "user-1", "users", 2, 3000, clock);

        assert_eq!(op.base_version, 2);
    }

    #[test]
    fn operation_accessors() {
        let clock = LogicalClock::with_counter("node-1", 1);
        let create = Operation::Create(CreateOp::new(
            "op-1",
            "user-1",
            "users",
            json!({}),
            1000,
            clock,
        ));

        assert_eq!(create.op_id(), "op-1");
        assert_eq!(create.record_id(), "user-1");
        assert_eq!(create.collection(), "users");
        assert_eq!(create.timestamp(), 1000);
    }

    #[test]
    fn operation_ordering() {
        let clock1 = LogicalClock::with_counter("node-1", 1);
        let clock2 = LogicalClock::with_counter("node-1", 2);

        let op1 = Operation::Create(CreateOp::new("op-1", "r1", "c", json!({}), 1000, clock1));
        let op2 = Operation::Create(CreateOp::new("op-2", "r2", "c", json!({}), 1000, clock2));

        assert!(op1 < op2); // clock1 < clock2
    }

    #[test]
    fn operation_ordering_same_clock_different_timestamp() {
        let clock = LogicalClock::with_counter("node-1", 1);

        let op1 = Operation::Create(CreateOp::new(
            "op-1",
            "r1",
            "c",
            json!({}),
            1000,
            clock.clone(),
        ));
        let op2 = Operation::Create(CreateOp::new("op-2", "r2", "c", json!({}), 2000, clock));

        assert!(op1 < op2); // earlier timestamp
    }

    #[test]
    fn serialization_create() {
        let clock = LogicalClock::with_counter("node-1", 1);
        let op = Operation::Create(CreateOp::new(
            "op-1",
            "user-1",
            "users",
            json!({"name": "Alice"}),
            1000,
            clock,
        ));

        let json = serde_json::to_string(&op).unwrap();
        assert!(json.contains("\"type\":\"create\""));

        let parsed: Operation = serde_json::from_str(&json).unwrap();
        assert_eq!(op, parsed);
    }

    #[test]
    fn serialization_update() {
        let clock = LogicalClock::with_counter("node-1", 2);
        let op = Operation::Update(UpdateOp::new(
            "op-2",
            "user-1",
            "users",
            json!({"name": "Bob"}),
            1,
            2000,
            clock,
        ));

        let json = serde_json::to_string(&op).unwrap();
        assert!(json.contains("\"type\":\"update\""));

        let parsed: Operation = serde_json::from_str(&json).unwrap();
        assert_eq!(op, parsed);
    }

    #[test]
    fn serialization_delete() {
        let clock = LogicalClock::with_counter("node-1", 3);
        let op = Operation::Delete(DeleteOp::new("op-3", "user-1", "users", 2, 3000, clock));

        let json = serde_json::to_string(&op).unwrap();
        assert!(json.contains("\"type\":\"delete\""));

        let parsed: Operation = serde_json::from_str(&json).unwrap();
        assert_eq!(op, parsed);
    }
}
