//! Snapshot types for persisting and restoring store state.
//!
//! Snapshots are the bridge between the in-memory Store and persistent storage.
//! They are designed for deterministic serialization to ensure consistency.

use crate::{
    error::Result, CollectionName, Error, LogicalClock, NodeId, PendingOp, Record, RecordId,
    Schema, SchemaVersion,
};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// Version of the snapshot format for future compatibility.
pub const SNAPSHOT_FORMAT_VERSION: u32 = 1;

/// A point-in-time snapshot of the store state.
///
/// This is the primary type for persisting store state to disk.
/// Uses BTreeMap instead of HashMap for deterministic serialization order.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StoreSnapshot {
    /// Snapshot format version
    pub format_version: u32,
    /// Schema version at time of snapshot
    pub schema_version: SchemaVersion,
    /// Node ID of the store
    pub node_id: NodeId,
    /// Current logical clock state
    pub clock: LogicalClock,
    /// All records organized by collection, then by record ID
    /// Using BTreeMap for deterministic ordering
    pub collections: BTreeMap<CollectionName, BTreeMap<RecordId, Record>>,
    /// Pending operations not yet synced
    pub pending_ops: Vec<PendingOp>,
}

impl StoreSnapshot {
    /// Create a new empty snapshot.
    pub fn new(schema_version: SchemaVersion, node_id: impl Into<NodeId>) -> Self {
        let node_id = node_id.into();
        Self {
            format_version: SNAPSHOT_FORMAT_VERSION,
            schema_version,
            node_id: node_id.clone(),
            clock: LogicalClock::new(node_id),
            collections: BTreeMap::new(),
            pending_ops: Vec::new(),
        }
    }

    /// Add a record to the snapshot.
    pub fn add_record(&mut self, record: Record) {
        self.collections
            .entry(record.collection.clone())
            .or_default()
            .insert(record.id.clone(), record);
    }

    /// Get a record from the snapshot.
    pub fn get_record(&self, collection: &str, id: &str) -> Option<&Record> {
        self.collections.get(collection)?.get(id)
    }

    /// Add a pending operation.
    pub fn add_pending(&mut self, pending: PendingOp) {
        self.pending_ops.push(pending);
    }

    /// Count total records across all collections.
    pub fn record_count(&self) -> usize {
        self.collections.values().map(|c| c.len()).sum()
    }

    /// Count active (non-deleted) records.
    pub fn active_record_count(&self) -> usize {
        self.collections
            .values()
            .flat_map(|c| c.values())
            .filter(|r| r.is_active())
            .count()
    }

    /// Validate the snapshot against a schema.
    pub fn validate(&self, schema: &Schema) -> Result<()> {
        // Check schema version
        if self.schema_version != schema.version {
            return Err(Error::SchemaVersionMismatch {
                expected: schema.version,
                actual: self.schema_version,
            });
        }

        // Check all collections exist in schema
        for collection_name in self.collections.keys() {
            if !schema.collections.contains_key(collection_name) {
                return Err(Error::CollectionNotFound(collection_name.clone()));
            }
        }

        // Validate all records against schema
        for (collection_name, records) in &self.collections {
            if let Some(collection_schema) = schema.collections.get(collection_name) {
                for record in records.values() {
                    if record.is_active() {
                        collection_schema.validate_payload(&record.payload)?;
                    }
                }
            }
        }

        Ok(())
    }

    /// Serialize to JSON with deterministic ordering.
    pub fn to_json(&self) -> Result<String> {
        serde_json::to_string(self).map_err(|e| Error::InvalidSnapshot(e.to_string()))
    }

    /// Serialize to pretty JSON with deterministic ordering.
    pub fn to_json_pretty(&self) -> Result<String> {
        serde_json::to_string_pretty(self).map_err(|e| Error::InvalidSnapshot(e.to_string()))
    }

    /// Deserialize from JSON.
    pub fn from_json(json: &str) -> Result<Self> {
        let snapshot: Self =
            serde_json::from_str(json).map_err(|e| Error::InvalidSnapshot(e.to_string()))?;

        // Validate format version
        if snapshot.format_version > SNAPSHOT_FORMAT_VERSION {
            return Err(Error::InvalidSnapshot(format!(
                "unsupported snapshot format version: {} (max supported: {})",
                snapshot.format_version, SNAPSHOT_FORMAT_VERSION
            )));
        }

        Ok(snapshot)
    }
}

/// Metadata about a snapshot (without the full data).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SnapshotMetadata {
    /// Snapshot format version
    pub format_version: u32,
    /// Schema version
    pub schema_version: SchemaVersion,
    /// Node ID
    pub node_id: NodeId,
    /// Clock counter at snapshot time
    pub clock_counter: u64,
    /// Total record count
    pub record_count: usize,
    /// Pending operation count
    pub pending_count: usize,
}

impl From<&StoreSnapshot> for SnapshotMetadata {
    fn from(snapshot: &StoreSnapshot) -> Self {
        Self {
            format_version: snapshot.format_version,
            schema_version: snapshot.schema_version,
            node_id: snapshot.node_id.clone(),
            clock_counter: snapshot.clock.counter,
            record_count: snapshot.record_count(),
            pending_count: snapshot.pending_ops.len(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::operation::CreateOp;
    use crate::schema::{CollectionSchema, FieldDef, FieldType};
    use crate::Operation;
    use serde_json::json;

    fn test_schema() -> Schema {
        Schema::new(1).with_collection(CollectionSchema::new(
            "users",
            vec![
                FieldDef::required("name", FieldType::String),
                FieldDef::optional("age", FieldType::Int),
            ],
        ))
    }

    #[test]
    fn create_empty_snapshot() {
        let snapshot = StoreSnapshot::new(1, "node-1");
        assert_eq!(snapshot.format_version, SNAPSHOT_FORMAT_VERSION);
        assert_eq!(snapshot.schema_version, 1);
        assert_eq!(snapshot.node_id, "node-1");
        assert_eq!(snapshot.record_count(), 0);
    }

    #[test]
    fn add_and_get_record() {
        let mut snapshot = StoreSnapshot::new(1, "node-1");

        let clock = LogicalClock::with_counter("node-1", 1);
        let record = Record::new("user-1", "users", json!({"name": "Alice"}), 1000, clock);

        snapshot.add_record(record);

        assert_eq!(snapshot.record_count(), 1);
        let retrieved = snapshot.get_record("users", "user-1").unwrap();
        assert_eq!(retrieved.payload, json!({"name": "Alice"}));
    }

    #[test]
    fn json_roundtrip() {
        let mut snapshot = StoreSnapshot::new(1, "node-1");

        let clock = LogicalClock::with_counter("node-1", 1);
        let record = Record::new(
            "user-1",
            "users",
            json!({"name": "Alice", "age": 30}),
            1000,
            clock.clone(),
        );
        snapshot.add_record(record);

        let pending = PendingOp {
            operation: Operation::Create(CreateOp::new(
                "op-1",
                "user-1",
                "users",
                json!({"name": "Alice", "age": 30}),
                1000,
                clock,
            )),
            applied_at: 1000,
        };
        snapshot.add_pending(pending);

        // Serialize
        let json = snapshot.to_json().unwrap();

        // Deserialize
        let restored = StoreSnapshot::from_json(&json).unwrap();

        assert_eq!(snapshot, restored);
    }

    #[test]
    fn deterministic_serialization() {
        let mut snapshot1 = StoreSnapshot::new(1, "node-1");
        let mut snapshot2 = StoreSnapshot::new(1, "node-1");

        // Add records in different order
        let clock = LogicalClock::with_counter("node-1", 1);

        snapshot1.add_record(Record::new(
            "user-a",
            "users",
            json!({"name": "Alice"}),
            1000,
            clock.clone(),
        ));
        snapshot1.add_record(Record::new(
            "user-b",
            "users",
            json!({"name": "Bob"}),
            1000,
            clock.clone(),
        ));

        // Add in reverse order
        snapshot2.add_record(Record::new(
            "user-b",
            "users",
            json!({"name": "Bob"}),
            1000,
            clock.clone(),
        ));
        snapshot2.add_record(Record::new(
            "user-a",
            "users",
            json!({"name": "Alice"}),
            1000,
            clock,
        ));

        // Serialization should be identical (BTreeMap ensures ordering)
        let json1 = snapshot1.to_json().unwrap();
        let json2 = snapshot2.to_json().unwrap();

        assert_eq!(json1, json2);
    }

    #[test]
    fn validate_snapshot_success() {
        let schema = test_schema();
        let mut snapshot = StoreSnapshot::new(1, "node-1");

        let clock = LogicalClock::with_counter("node-1", 1);
        snapshot.add_record(Record::new(
            "user-1",
            "users",
            json!({"name": "Alice", "age": 30}),
            1000,
            clock,
        ));

        assert!(snapshot.validate(&schema).is_ok());
    }

    #[test]
    fn validate_snapshot_schema_version_mismatch() {
        let schema = test_schema();
        let snapshot = StoreSnapshot::new(99, "node-1"); // Wrong version

        let result = snapshot.validate(&schema);
        assert!(matches!(result, Err(Error::SchemaVersionMismatch { .. })));
    }

    #[test]
    fn validate_snapshot_invalid_payload() {
        let schema = test_schema();
        let mut snapshot = StoreSnapshot::new(1, "node-1");

        let clock = LogicalClock::with_counter("node-1", 1);
        snapshot.add_record(Record::new(
            "user-1",
            "users",
            json!({"name": 123}), // name should be string
            1000,
            clock,
        ));

        let result = snapshot.validate(&schema);
        assert!(matches!(result, Err(Error::TypeMismatch { .. })));
    }

    #[test]
    fn snapshot_metadata() {
        let mut snapshot = StoreSnapshot::new(1, "node-1");
        snapshot.clock.counter = 42;

        let clock = LogicalClock::with_counter("node-1", 1);
        snapshot.add_record(Record::new(
            "user-1",
            "users",
            json!({"name": "Alice"}),
            1000,
            clock.clone(),
        ));
        snapshot.add_pending(PendingOp {
            operation: Operation::Create(CreateOp::new(
                "op-1",
                "user-1",
                "users",
                json!({"name": "Alice"}),
                1000,
                clock,
            )),
            applied_at: 1000,
        });

        let metadata: SnapshotMetadata = (&snapshot).into();

        assert_eq!(metadata.format_version, SNAPSHOT_FORMAT_VERSION);
        assert_eq!(metadata.schema_version, 1);
        assert_eq!(metadata.node_id, "node-1");
        assert_eq!(metadata.clock_counter, 42);
        assert_eq!(metadata.record_count, 1);
        assert_eq!(metadata.pending_count, 1);
    }

    #[test]
    fn reject_future_format_version() {
        let json = r#"{
            "formatVersion": 999,
            "schemaVersion": 1,
            "nodeId": "node-1",
            "clock": {"nodeId": "node-1", "counter": 0},
            "collections": {},
            "pendingOps": []
        }"#;

        let result = StoreSnapshot::from_json(json);
        assert!(matches!(result, Err(Error::InvalidSnapshot(_))));
    }

    #[test]
    fn active_record_count() {
        let mut snapshot = StoreSnapshot::new(1, "node-1");
        let clock = LogicalClock::with_counter("node-1", 1);

        // Active record
        snapshot.add_record(Record::new(
            "user-1",
            "users",
            json!({"name": "Alice"}),
            1000,
            clock.clone(),
        ));

        // Deleted record
        let mut deleted = Record::new(
            "user-2",
            "users",
            json!({"name": "Bob"}),
            1000,
            clock.clone(),
        );
        deleted.deleted = true;
        snapshot.add_record(deleted);

        assert_eq!(snapshot.record_count(), 2);
        assert_eq!(snapshot.active_record_count(), 1);
    }
}
