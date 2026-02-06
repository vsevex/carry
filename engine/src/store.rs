//! Store - the in-memory state container.
//!
//! The Store holds all records and pending operations. It applies operations
//! locally and tracks what needs to be synced.

use crate::{
    error::Result, CollectionName, Error, LogicalClock, NodeId, Operation, OperationId, Record,
    RecordId, Schema, Timestamp, Version,
};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// A collection of records.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Collection {
    records: HashMap<RecordId, Record>,
}

impl Collection {
    /// Create an empty collection.
    pub fn new() -> Self {
        Self {
            records: HashMap::new(),
        }
    }

    /// Get a record by ID.
    pub fn get(&self, id: &str) -> Option<&Record> {
        self.records.get(id)
    }

    /// Get a mutable record by ID.
    pub fn get_mut(&mut self, id: &str) -> Option<&mut Record> {
        self.records.get_mut(id)
    }

    /// Insert a record.
    pub fn insert(&mut self, record: Record) {
        self.records.insert(record.id.clone(), record);
    }

    /// Check if a record exists (including deleted).
    pub fn contains(&self, id: &str) -> bool {
        self.records.contains_key(id)
    }

    /// Get all active (non-deleted) records.
    pub fn active_records(&self) -> impl Iterator<Item = &Record> {
        self.records.values().filter(|r| r.is_active())
    }

    /// Get all records including deleted.
    pub fn all_records(&self) -> impl Iterator<Item = &Record> {
        self.records.values()
    }

    /// Count of active records.
    pub fn len(&self) -> usize {
        self.records.values().filter(|r| r.is_active()).count()
    }

    /// Check if collection has no active records.
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
}

/// Result of applying an operation.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ApplyResult {
    /// The operation ID that was applied
    pub op_id: OperationId,
    /// The record ID affected
    pub record_id: RecordId,
    /// The new version of the record
    pub version: Version,
}

/// A pending operation waiting to be synced.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PendingOp {
    /// The operation
    pub operation: Operation,
    /// When it was applied locally
    pub applied_at: Timestamp,
}

/// The main store holding all state.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Store {
    /// Schema for validation
    schema: Schema,
    /// Node ID for this store instance
    node_id: NodeId,
    /// Logical clock for ordering
    clock: LogicalClock,
    /// Collections by name
    collections: HashMap<CollectionName, Collection>,
    /// Operations pending sync
    pending_ops: Vec<PendingOp>,
}

impl Store {
    /// Create a new store with the given schema and node ID.
    pub fn new(schema: Schema, node_id: impl Into<NodeId>) -> Self {
        let node_id = node_id.into();
        let clock = LogicalClock::new(node_id.clone());

        // Initialize empty collections for all schema-defined collections
        let mut collections = HashMap::new();
        for name in schema.collections.keys() {
            collections.insert(name.clone(), Collection::new());
        }

        Self {
            schema,
            node_id,
            clock,
            collections,
            pending_ops: Vec::new(),
        }
    }

    /// Get the node ID.
    pub fn node_id(&self) -> &NodeId {
        &self.node_id
    }

    /// Get the current logical clock.
    pub fn clock(&self) -> &LogicalClock {
        &self.clock
    }

    /// Get the schema.
    pub fn schema(&self) -> &Schema {
        &self.schema
    }

    /// Tick the clock and return a clone of the new value.
    pub fn tick(&mut self) -> LogicalClock {
        self.clock.tick();
        self.clock.clone()
    }

    /// Apply an operation to the store.
    ///
    /// This validates the operation, applies it, and adds it to pending ops.
    pub fn apply(&mut self, op: Operation, timestamp: Timestamp) -> Result<ApplyResult> {
        // Validate against schema
        self.schema.validate_operation(&op)?;

        // Update clock from operation
        self.clock.merge(op.clock());

        // Apply the operation
        let result = match &op {
            Operation::Create(create_op) => self.apply_create(create_op, timestamp)?,
            Operation::Update(update_op) => self.apply_update(update_op, timestamp)?,
            Operation::Delete(delete_op) => self.apply_delete(delete_op, timestamp)?,
        };

        // Track as pending
        self.pending_ops.push(PendingOp {
            operation: op,
            applied_at: timestamp,
        });

        Ok(result)
    }

    fn apply_create(&mut self, op: &crate::CreateOp, timestamp: Timestamp) -> Result<ApplyResult> {
        let collection = self
            .collections
            .get_mut(&op.collection)
            .ok_or_else(|| Error::CollectionNotFound(op.collection.clone()))?;

        // Check if record already exists
        if let Some(existing) = collection.get(&op.id) {
            if existing.is_active() {
                return Err(Error::RecordAlreadyExists(op.id.clone()));
            }
            // If deleted, we could potentially resurrect, but for v1 we reject
            return Err(Error::RecordAlreadyExists(op.id.clone()));
        }

        // Create the record
        let record = Record::new(
            op.id.clone(),
            op.collection.clone(),
            op.payload.clone(),
            timestamp,
            op.clock.clone(),
        );

        let version = record.version;
        collection.insert(record);

        Ok(ApplyResult {
            op_id: op.op_id.clone(),
            record_id: op.id.clone(),
            version,
        })
    }

    fn apply_update(&mut self, op: &crate::UpdateOp, timestamp: Timestamp) -> Result<ApplyResult> {
        let collection = self
            .collections
            .get_mut(&op.collection)
            .ok_or_else(|| Error::CollectionNotFound(op.collection.clone()))?;

        let record = collection
            .get_mut(&op.id)
            .ok_or_else(|| Error::RecordNotFound(op.id.clone()))?;

        // Check if deleted
        if record.deleted {
            return Err(Error::OperationOnDeleted(op.id.clone()));
        }

        // Check version
        if record.version != op.base_version {
            return Err(Error::VersionMismatch {
                expected: op.base_version,
                actual: record.version,
            });
        }

        // Apply update
        record.update_payload(
            op.payload.clone(),
            timestamp,
            op.clock.clone(),
            crate::record::Origin::Local,
        );

        Ok(ApplyResult {
            op_id: op.op_id.clone(),
            record_id: op.id.clone(),
            version: record.version,
        })
    }

    fn apply_delete(&mut self, op: &crate::DeleteOp, timestamp: Timestamp) -> Result<ApplyResult> {
        let collection = self
            .collections
            .get_mut(&op.collection)
            .ok_or_else(|| Error::CollectionNotFound(op.collection.clone()))?;

        let record = collection
            .get_mut(&op.id)
            .ok_or_else(|| Error::RecordNotFound(op.id.clone()))?;

        // Check if already deleted
        if record.deleted {
            return Err(Error::OperationOnDeleted(op.id.clone()));
        }

        // Check version
        if record.version != op.base_version {
            return Err(Error::VersionMismatch {
                expected: op.base_version,
                actual: record.version,
            });
        }

        // Apply delete
        record.mark_deleted(timestamp, op.clock.clone(), crate::record::Origin::Local);

        Ok(ApplyResult {
            op_id: op.op_id.clone(),
            record_id: op.id.clone(),
            version: record.version,
        })
    }

    /// Get a record by collection and ID.
    pub fn get(&self, collection: &str, id: &str) -> Option<&Record> {
        self.collections
            .get(collection)
            .and_then(|c| c.get(id))
            .filter(|r| r.is_active())
    }

    /// Get a record including deleted ones.
    pub fn get_including_deleted(&self, collection: &str, id: &str) -> Option<&Record> {
        self.collections.get(collection).and_then(|c| c.get(id))
    }

    /// Query records in a collection.
    pub fn query(&self, collection: &str) -> Option<QueryBuilder<'_>> {
        self.collections.get(collection).map(QueryBuilder::new)
    }

    /// Get all pending operations.
    pub fn pending_ops(&self) -> &[PendingOp] {
        &self.pending_ops
    }

    /// Get count of pending operations.
    pub fn pending_count(&self) -> usize {
        self.pending_ops.len()
    }

    /// Acknowledge operations as synced (remove from pending).
    pub fn acknowledge(&mut self, op_ids: &[OperationId]) {
        self.pending_ops
            .retain(|p| !op_ids.contains(p.operation.op_id()));
    }

    /// Clear all pending operations.
    pub fn clear_pending(&mut self) {
        self.pending_ops.clear();
    }

    /// Get a collection by name.
    pub fn collection(&self, name: &str) -> Option<&Collection> {
        self.collections.get(name)
    }

    /// Reconcile local pending operations with remote operations.
    ///
    /// This is the core sync operation:
    /// 1. Takes pending local ops and incoming remote ops
    /// 2. Orders all ops deterministically
    /// 3. Resolves conflicts using the specified strategy
    /// 4. Updates store state to match reconciled result
    /// 5. Returns details about what was accepted/rejected
    pub fn reconcile(
        &mut self,
        remote_ops: Vec<Operation>,
        strategy: crate::reconcile::MergeStrategy,
    ) -> crate::reconcile::ReconcileResult {
        use crate::reconcile::{OpSource, Reconciler};

        // Create reconciler with current schema
        let mut reconciler = Reconciler::new(&self.schema, strategy);

        // Load existing records with their last operations
        // For existing records, we create synthetic "create" ops to track state
        for (collection_name, collection) in &self.collections {
            for record in collection.all_records() {
                // Create a synthetic operation representing current state
                let synthetic_op = Operation::Create(crate::CreateOp::new(
                    format!("__existing__{}", record.id),
                    record.id.clone(),
                    collection_name.clone(),
                    record.payload.clone(),
                    record.metadata.created_at,
                    record.metadata.clock.clone(),
                ));
                reconciler.load_records(std::iter::once((
                    record.clone(),
                    synthetic_op,
                    match record.metadata.origin {
                        crate::record::Origin::Local => OpSource::Local,
                        crate::record::Origin::Remote => OpSource::Remote,
                    },
                )));
            }
        }

        // Extract pending operations
        let local_ops: Vec<_> = self
            .pending_ops
            .iter()
            .map(|p| p.operation.clone())
            .collect();

        // Run reconciliation
        let (result, final_records) = reconciler.reconcile(local_ops, remote_ops);

        // Update store state from reconciled records
        for ((collection_name, _record_id), record) in final_records {
            if let Some(collection) = self.collections.get_mut(&collection_name) {
                collection.insert(record);
            }
        }

        // Remove rejected local ops from pending (they lost conflict resolution)
        let before_retain = self.pending_ops.len();
        self.pending_ops
            .retain(|p| !result.rejected_local.contains(p.operation.op_id()));
        let after_retain = self.pending_ops.len();

        // NOTE: Accepted local ops are NOT removed here - they remain pending
        // until the server acknowledges them via the acknowledge() method.
        // This ensures ops are pushed to the server before being cleared.

        // Debug: Add pending count to result for verification (v2 fix)
        let mut result = result;
        result.debug_pending_before = Some(before_retain);
        result.debug_pending_after = Some(after_retain);

        result
    }

    /// Export the current store state as a snapshot.
    ///
    /// The snapshot can be serialized and persisted by the Flutter layer.
    pub fn export_state(&self) -> crate::snapshot::StoreSnapshot {
        let mut snapshot =
            crate::snapshot::StoreSnapshot::new(self.schema.version, self.node_id.clone());
        snapshot.clock = self.clock.clone();

        // Export all records from all collections
        for collection in self.collections.values() {
            for record in collection.all_records() {
                snapshot.add_record(record.clone());
            }
        }

        // Export pending operations
        for pending in &self.pending_ops {
            snapshot.add_pending(pending.clone());
        }

        snapshot
    }

    /// Import state from a snapshot.
    ///
    /// This replaces the current state with the snapshot's state.
    /// The schema must match.
    pub fn import_state(&mut self, snapshot: crate::snapshot::StoreSnapshot) -> Result<()> {
        // Validate against current schema
        snapshot.validate(&self.schema)?;

        // Validate node ID matches
        if snapshot.node_id != self.node_id {
            return Err(Error::InvalidSnapshot(format!(
                "node ID mismatch: expected '{}', got '{}'",
                self.node_id, snapshot.node_id
            )));
        }

        // Import clock
        self.clock = snapshot.clock;

        // Clear and import collections
        for collection in self.collections.values_mut() {
            collection.records.clear();
        }

        for (collection_name, records) in snapshot.collections {
            if let Some(collection) = self.collections.get_mut(&collection_name) {
                for (_, record) in records {
                    collection.insert(record);
                }
            }
        }

        // Import pending operations
        self.pending_ops = snapshot.pending_ops;

        Ok(())
    }

    /// Get snapshot metadata without full export.
    pub fn snapshot_metadata(&self) -> crate::snapshot::SnapshotMetadata {
        crate::snapshot::SnapshotMetadata {
            format_version: crate::snapshot::SNAPSHOT_FORMAT_VERSION,
            schema_version: self.schema.version,
            node_id: self.node_id.clone(),
            clock_counter: self.clock.counter,
            record_count: self.collections.values().map(|c| c.records.len()).sum(),
            pending_count: self.pending_ops.len(),
        }
    }
}

/// Builder for querying records in a collection.
#[derive(Debug)]
pub struct QueryBuilder<'a> {
    collection: &'a Collection,
    include_deleted: bool,
}

impl<'a> QueryBuilder<'a> {
    fn new(collection: &'a Collection) -> Self {
        Self {
            collection,
            include_deleted: false,
        }
    }

    /// Include deleted records in results.
    pub fn include_deleted(mut self) -> Self {
        self.include_deleted = true;
        self
    }

    /// Get all matching records.
    pub fn all(self) -> Vec<&'a Record> {
        if self.include_deleted {
            self.collection.all_records().collect()
        } else {
            self.collection.active_records().collect()
        }
    }

    /// Get the first matching record.
    pub fn first(self) -> Option<&'a Record> {
        if self.include_deleted {
            self.collection.all_records().next()
        } else {
            self.collection.active_records().next()
        }
    }

    /// Count matching records.
    pub fn count(self) -> usize {
        if self.include_deleted {
            self.collection.records.len()
        } else {
            self.collection.len()
        }
    }

    /// Filter records by a predicate on payload.
    pub fn filter<F>(self, predicate: F) -> Vec<&'a Record>
    where
        F: Fn(&serde_json::Value) -> bool,
    {
        let iter: Box<dyn Iterator<Item = &Record>> = if self.include_deleted {
            Box::new(self.collection.all_records())
        } else {
            Box::new(self.collection.active_records())
        };

        iter.filter(|r| predicate(&r.payload)).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::operation::{CreateOp, DeleteOp, UpdateOp};
    use crate::schema::{CollectionSchema, FieldDef, FieldType};
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

    fn test_store() -> Store {
        Store::new(test_schema(), "test-node")
    }

    #[test]
    fn create_store() {
        let store = test_store();
        assert_eq!(store.node_id(), "test-node");
        assert_eq!(store.clock().counter, 0);
        assert!(store.collection("users").is_some());
    }

    #[test]
    fn apply_create() {
        let mut store = test_store();
        let clock = store.tick();

        let op = Operation::Create(CreateOp::new(
            "op-1",
            "user-1",
            "users",
            json!({"name": "Alice"}),
            1000,
            clock,
        ));

        let result = store.apply(op, 1000).unwrap();
        assert_eq!(result.record_id, "user-1");
        assert_eq!(result.version, 1);

        let record = store.get("users", "user-1").unwrap();
        assert_eq!(record.payload, json!({"name": "Alice"}));
    }

    #[test]
    fn apply_create_duplicate() {
        let mut store = test_store();
        let clock = store.tick();

        let op = Operation::Create(CreateOp::new(
            "op-1",
            "user-1",
            "users",
            json!({"name": "Alice"}),
            1000,
            clock,
        ));
        store.apply(op, 1000).unwrap();

        // Try to create same ID again
        let clock2 = store.tick();
        let op2 = Operation::Create(CreateOp::new(
            "op-2",
            "user-1",
            "users",
            json!({"name": "Bob"}),
            2000,
            clock2,
        ));

        let result = store.apply(op2, 2000);
        assert!(matches!(result, Err(Error::RecordAlreadyExists(_))));
    }

    #[test]
    fn apply_update() {
        let mut store = test_store();

        // Create first
        let clock1 = store.tick();
        let create = Operation::Create(CreateOp::new(
            "op-1",
            "user-1",
            "users",
            json!({"name": "Alice"}),
            1000,
            clock1,
        ));
        store.apply(create, 1000).unwrap();

        // Update
        let clock2 = store.tick();
        let update = Operation::Update(UpdateOp::new(
            "op-2",
            "user-1",
            "users",
            json!({"name": "Alice Smith", "age": 30}),
            1, // base_version
            2000,
            clock2,
        ));
        let result = store.apply(update, 2000).unwrap();
        assert_eq!(result.version, 2);

        let record = store.get("users", "user-1").unwrap();
        assert_eq!(record.payload, json!({"name": "Alice Smith", "age": 30}));
    }

    #[test]
    fn apply_update_version_mismatch() {
        let mut store = test_store();

        // Create
        let clock1 = store.tick();
        let create = Operation::Create(CreateOp::new(
            "op-1",
            "user-1",
            "users",
            json!({"name": "Alice"}),
            1000,
            clock1,
        ));
        store.apply(create, 1000).unwrap();

        // Update with wrong base version
        let clock2 = store.tick();
        let update = Operation::Update(UpdateOp::new(
            "op-2",
            "user-1",
            "users",
            json!({"name": "Alice Smith"}),
            5, // wrong base_version
            2000,
            clock2,
        ));

        let result = store.apply(update, 2000);
        assert!(matches!(
            result,
            Err(Error::VersionMismatch {
                expected: 5,
                actual: 1
            })
        ));
    }

    #[test]
    fn apply_delete() {
        let mut store = test_store();

        // Create
        let clock1 = store.tick();
        let create = Operation::Create(CreateOp::new(
            "op-1",
            "user-1",
            "users",
            json!({"name": "Alice"}),
            1000,
            clock1,
        ));
        store.apply(create, 1000).unwrap();

        // Delete
        let clock2 = store.tick();
        let delete = Operation::Delete(DeleteOp::new("op-2", "user-1", "users", 1, 2000, clock2));
        let result = store.apply(delete, 2000).unwrap();
        assert_eq!(result.version, 2);

        // Should not be found via normal get
        assert!(store.get("users", "user-1").is_none());

        // But should be found including deleted
        let record = store.get_including_deleted("users", "user-1").unwrap();
        assert!(record.deleted);
    }

    #[test]
    fn apply_update_on_deleted() {
        let mut store = test_store();

        // Create and delete
        let clock1 = store.tick();
        store
            .apply(
                Operation::Create(CreateOp::new(
                    "op-1",
                    "user-1",
                    "users",
                    json!({"name": "Alice"}),
                    1000,
                    clock1,
                )),
                1000,
            )
            .unwrap();

        let clock2 = store.tick();
        store
            .apply(
                Operation::Delete(DeleteOp::new("op-2", "user-1", "users", 1, 2000, clock2)),
                2000,
            )
            .unwrap();

        // Try to update deleted record
        let clock3 = store.tick();
        let update = Operation::Update(UpdateOp::new(
            "op-3",
            "user-1",
            "users",
            json!({"name": "Alice Smith"}),
            2,
            3000,
            clock3,
        ));

        let result = store.apply(update, 3000);
        assert!(matches!(result, Err(Error::OperationOnDeleted(_))));
    }

    #[test]
    fn pending_ops_tracking() {
        let mut store = test_store();

        let clock1 = store.tick();
        store
            .apply(
                Operation::Create(CreateOp::new(
                    "op-1",
                    "user-1",
                    "users",
                    json!({"name": "Alice"}),
                    1000,
                    clock1,
                )),
                1000,
            )
            .unwrap();

        let clock2 = store.tick();
        store
            .apply(
                Operation::Create(CreateOp::new(
                    "op-2",
                    "user-2",
                    "users",
                    json!({"name": "Bob"}),
                    2000,
                    clock2,
                )),
                2000,
            )
            .unwrap();

        assert_eq!(store.pending_count(), 2);

        // Acknowledge one
        store.acknowledge(&["op-1".to_string()]);
        assert_eq!(store.pending_count(), 1);
        assert_eq!(store.pending_ops()[0].operation.op_id(), "op-2");
    }

    #[test]
    fn query_all() {
        let mut store = test_store();

        let clock1 = store.tick();
        store
            .apply(
                Operation::Create(CreateOp::new(
                    "op-1",
                    "user-1",
                    "users",
                    json!({"name": "Alice"}),
                    1000,
                    clock1,
                )),
                1000,
            )
            .unwrap();

        let clock2 = store.tick();
        store
            .apply(
                Operation::Create(CreateOp::new(
                    "op-2",
                    "user-2",
                    "users",
                    json!({"name": "Bob"}),
                    2000,
                    clock2,
                )),
                2000,
            )
            .unwrap();

        let results = store.query("users").unwrap().all();
        assert_eq!(results.len(), 2);
    }

    #[test]
    fn query_filter() {
        let mut store = test_store();

        let clock1 = store.tick();
        store
            .apply(
                Operation::Create(CreateOp::new(
                    "op-1",
                    "user-1",
                    "users",
                    json!({"name": "Alice", "age": 30}),
                    1000,
                    clock1,
                )),
                1000,
            )
            .unwrap();

        let clock2 = store.tick();
        store
            .apply(
                Operation::Create(CreateOp::new(
                    "op-2",
                    "user-2",
                    "users",
                    json!({"name": "Bob", "age": 25}),
                    2000,
                    clock2,
                )),
                2000,
            )
            .unwrap();

        let results = store.query("users").unwrap().filter(|payload| {
            payload
                .get("age")
                .and_then(|v| v.as_i64())
                .map(|age| age >= 30)
                .unwrap_or(false)
        });

        assert_eq!(results.len(), 1);
        assert_eq!(results[0].id, "user-1");
    }

    #[test]
    fn query_include_deleted() {
        let mut store = test_store();

        // Create two users
        let clock1 = store.tick();
        store
            .apply(
                Operation::Create(CreateOp::new(
                    "op-1",
                    "user-1",
                    "users",
                    json!({"name": "Alice"}),
                    1000,
                    clock1,
                )),
                1000,
            )
            .unwrap();

        let clock2 = store.tick();
        store
            .apply(
                Operation::Create(CreateOp::new(
                    "op-2",
                    "user-2",
                    "users",
                    json!({"name": "Bob"}),
                    2000,
                    clock2,
                )),
                2000,
            )
            .unwrap();

        // Delete one
        let clock3 = store.tick();
        store
            .apply(
                Operation::Delete(DeleteOp::new("op-3", "user-1", "users", 1, 3000, clock3)),
                3000,
            )
            .unwrap();

        // Without deleted
        assert_eq!(store.query("users").unwrap().count(), 1);

        // With deleted
        assert_eq!(store.query("users").unwrap().include_deleted().count(), 2);
    }

    #[test]
    fn collection_not_found() {
        let mut store = test_store();
        let clock = store.tick();

        let op = Operation::Create(CreateOp::new(
            "op-1",
            "post-1",
            "posts", // doesn't exist
            json!({"title": "Hello"}),
            1000,
            clock,
        ));

        let result = store.apply(op, 1000);
        assert!(matches!(result, Err(Error::CollectionNotFound(_))));
    }

    #[test]
    fn record_not_found() {
        let mut store = test_store();
        let clock = store.tick();

        let op = Operation::Update(UpdateOp::new(
            "op-1",
            "user-999",
            "users",
            json!({"name": "Ghost"}),
            1,
            1000,
            clock,
        ));

        let result = store.apply(op, 1000);
        assert!(matches!(result, Err(Error::RecordNotFound(_))));
    }

    #[test]
    fn store_serialization() {
        let mut store = test_store();

        let clock = store.tick();
        store
            .apply(
                Operation::Create(CreateOp::new(
                    "op-1",
                    "user-1",
                    "users",
                    json!({"name": "Alice"}),
                    1000,
                    clock,
                )),
                1000,
            )
            .unwrap();

        let json = serde_json::to_string(&store).unwrap();
        let restored: Store = serde_json::from_str(&json).unwrap();

        assert_eq!(restored.node_id(), store.node_id());
        assert!(restored.get("users", "user-1").is_some());
    }

    #[test]
    fn store_reconcile_with_remote() {
        use crate::reconcile::MergeStrategy;
        use crate::LogicalClock;

        let mut store = test_store();

        // Local creates user-1
        let clock1 = store.tick();
        store
            .apply(
                Operation::Create(CreateOp::new(
                    "op-local",
                    "user-1",
                    "users",
                    json!({"name": "Alice"}),
                    1000,
                    clock1,
                )),
                1000,
            )
            .unwrap();

        assert_eq!(store.pending_count(), 1);

        // Remote has user-1 with higher clock (wins) and user-2
        let remote_ops = vec![
            Operation::Create(CreateOp::new(
                "op-remote-1",
                "user-1",
                "users",
                json!({"name": "Bob"}),
                1000,
                LogicalClock::with_counter("remote", 10), // higher clock wins
            )),
            Operation::Create(CreateOp::new(
                "op-remote-2",
                "user-2",
                "users",
                json!({"name": "Charlie"}),
                1000,
                LogicalClock::with_counter("remote", 5),
            )),
        ];

        let result = store.reconcile(remote_ops, MergeStrategy::ClockWins);

        // Local op was rejected (remote had higher clock)
        assert_eq!(result.rejected_local.len(), 1);
        assert_eq!(result.conflicts.len(), 1);

        // Pending should be cleared (local op rejected or accepted)
        assert_eq!(store.pending_count(), 0);

        // user-1 should have Bob (remote won)
        let user1 = store.get("users", "user-1").unwrap();
        assert_eq!(user1.payload, json!({"name": "Bob"}));

        // user-2 should exist
        let user2 = store.get("users", "user-2").unwrap();
        assert_eq!(user2.payload, json!({"name": "Charlie"}));
    }

    #[test]
    fn store_reconcile_local_wins() {
        use crate::reconcile::MergeStrategy;
        use crate::LogicalClock;

        let mut store = test_store();

        // Local creates user-1 with high clock
        let mut clock = store.tick();
        clock.counter = 20; // simulate high counter
        store
            .apply(
                Operation::Create(CreateOp::new(
                    "op-local",
                    "user-1",
                    "users",
                    json!({"name": "Alice"}),
                    1000,
                    clock,
                )),
                1000,
            )
            .unwrap();

        // Remote has user-1 with lower clock
        let remote_ops = vec![Operation::Create(CreateOp::new(
            "op-remote",
            "user-1",
            "users",
            json!({"name": "Bob"}),
            1000,
            LogicalClock::with_counter("remote", 5), // lower clock
        ))];

        let result = store.reconcile(remote_ops, MergeStrategy::ClockWins);

        // Remote was rejected
        assert_eq!(result.rejected_remote.len(), 1);
        assert!(result.rejected_local.is_empty());

        // user-1 should have Alice (local won)
        let user1 = store.get("users", "user-1").unwrap();
        assert_eq!(user1.payload, json!({"name": "Alice"}));
    }

    #[test]
    fn export_import_roundtrip() {
        let mut store = test_store();

        // Add some data
        let clock1 = store.tick();
        store
            .apply(
                Operation::Create(CreateOp::new(
                    "op-1",
                    "user-1",
                    "users",
                    json!({"name": "Alice", "age": 30}),
                    1000,
                    clock1,
                )),
                1000,
            )
            .unwrap();

        let clock2 = store.tick();
        store
            .apply(
                Operation::Create(CreateOp::new(
                    "op-2",
                    "user-2",
                    "users",
                    json!({"name": "Bob"}),
                    2000,
                    clock2,
                )),
                2000,
            )
            .unwrap();

        // Export
        let snapshot = store.export_state();
        assert_eq!(snapshot.record_count(), 2);
        assert_eq!(snapshot.pending_ops.len(), 2);

        // Create a new store and import
        let mut store2 = test_store();
        store2.import_state(snapshot).unwrap();

        // Verify data was imported
        assert!(store2.get("users", "user-1").is_some());
        assert!(store2.get("users", "user-2").is_some());
        assert_eq!(store2.pending_count(), 2);

        let user1 = store2.get("users", "user-1").unwrap();
        assert_eq!(user1.payload, json!({"name": "Alice", "age": 30}));
    }

    #[test]
    fn export_to_json_roundtrip() {
        let mut store = test_store();

        let clock = store.tick();
        store
            .apply(
                Operation::Create(CreateOp::new(
                    "op-1",
                    "user-1",
                    "users",
                    json!({"name": "Alice"}),
                    1000,
                    clock,
                )),
                1000,
            )
            .unwrap();

        // Export to JSON
        let snapshot = store.export_state();
        let json = snapshot.to_json().unwrap();

        // Parse and import
        let parsed = crate::snapshot::StoreSnapshot::from_json(&json).unwrap();
        let mut store2 = test_store();
        store2.import_state(parsed).unwrap();

        // Verify
        let user = store2.get("users", "user-1").unwrap();
        assert_eq!(user.payload, json!({"name": "Alice"}));
    }

    #[test]
    fn import_node_id_mismatch() {
        // Create snapshot with different node ID
        let snapshot = crate::snapshot::StoreSnapshot::new(1, "different-node");

        let mut store2 = test_store();
        let result = store2.import_state(snapshot);

        assert!(matches!(result, Err(Error::InvalidSnapshot(_))));
    }

    #[test]
    fn snapshot_metadata() {
        let mut store = test_store();

        let clock = store.tick();
        store
            .apply(
                Operation::Create(CreateOp::new(
                    "op-1",
                    "user-1",
                    "users",
                    json!({"name": "Alice"}),
                    1000,
                    clock,
                )),
                1000,
            )
            .unwrap();

        let metadata = store.snapshot_metadata();

        assert_eq!(metadata.node_id, "test-node");
        assert_eq!(metadata.schema_version, 1);
        assert_eq!(metadata.record_count, 1);
        assert_eq!(metadata.pending_count, 1);
    }
}
