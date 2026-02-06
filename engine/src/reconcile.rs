//! Reconciliation logic for syncing local and remote state.
//!
//! This is the core of determinism. Given local pending operations and
//! remote operations, this module produces a consistent merged state.
//!
//! # Algorithm
//!
//! 1. Collect all operations (local pending + remote)
//! 2. Sort by (clock, timestamp, op_id) for total ordering
//! 3. Apply in order, detecting conflicts on same record
//! 4. Resolve conflicts using merge strategy
//! 5. Return new state and conflict details

use crate::{record::Origin, CollectionName, Operation, OperationId, Record, RecordId, Schema};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};

/// Merge strategy for conflict resolution.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum MergeStrategy {
    /// Higher clock wins, ties broken by node_id (default)
    #[default]
    ClockWins,
    /// Later timestamp wins (use with caution - clock skew issues)
    TimestampWins,
}

/// How a conflict was resolved.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ConflictResolution {
    /// Local operation won
    LocalWins,
    /// Remote operation won
    RemoteWins,
}

/// A detected conflict between operations.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Conflict {
    /// The local operation that conflicted
    pub local_op: Operation,
    /// The remote operation that conflicted
    pub remote_op: Operation,
    /// How the conflict was resolved
    pub resolution: ConflictResolution,
    /// The winning operation ID
    pub winner_op_id: OperationId,
}

/// Result of reconciliation.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReconcileResult {
    /// Local operations that were accepted (no conflict or won)
    pub accepted_local: Vec<OperationId>,
    /// Local operations that were rejected (lost conflict)
    pub rejected_local: Vec<OperationId>,
    /// Remote operations that were applied
    pub applied_remote: Vec<OperationId>,
    /// Remote operations that were rejected (lost to local)
    pub rejected_remote: Vec<OperationId>,
    /// Detected conflicts with resolution details
    pub conflicts: Vec<Conflict>,
    /// Debug: pending ops count before retain (v2 marker)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub debug_pending_before: Option<usize>,
    /// Debug: pending ops count after retain
    #[serde(skip_serializing_if = "Option::is_none")]
    pub debug_pending_after: Option<usize>,
}

impl ReconcileResult {
    fn new() -> Self {
        Self {
            accepted_local: Vec::new(),
            rejected_local: Vec::new(),
            applied_remote: Vec::new(),
            rejected_remote: Vec::new(),
            conflicts: Vec::new(),
            debug_pending_before: None,
            debug_pending_after: None,
        }
    }
}

/// Source of an operation (for tracking during reconciliation).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OpSource {
    Local,
    Remote,
}

/// An operation with its source tracked.
#[derive(Debug, Clone)]
struct TrackedOp {
    operation: Operation,
    source: OpSource,
}

impl TrackedOp {
    fn local(op: Operation) -> Self {
        Self {
            operation: op,
            source: OpSource::Local,
        }
    }

    fn remote(op: Operation) -> Self {
        Self {
            operation: op,
            source: OpSource::Remote,
        }
    }
}

/// Internal record state during reconciliation.
#[derive(Debug, Clone)]
struct RecordState {
    record: Record,
    /// The operation that last modified this record
    last_op: Operation,
    /// Source of the last operation
    last_source: OpSource,
}

/// The reconciler applies operations and resolves conflicts.
pub struct Reconciler<'a> {
    #[allow(dead_code)]
    schema: &'a Schema,
    strategy: MergeStrategy,
    /// Current state of records during reconciliation
    records: HashMap<(CollectionName, RecordId), RecordState>,
    /// Result being built
    result: ReconcileResult,
}

impl<'a> Reconciler<'a> {
    /// Create a new reconciler.
    pub fn new(schema: &'a Schema, strategy: MergeStrategy) -> Self {
        Self {
            schema,
            strategy,
            records: HashMap::new(),
            result: ReconcileResult::new(),
        }
    }

    /// Load existing records into the reconciler.
    pub fn load_records(&mut self, records: impl Iterator<Item = (Record, Operation, OpSource)>) {
        for (record, last_op, source) in records {
            let key = (record.collection.clone(), record.id.clone());
            self.records.insert(
                key,
                RecordState {
                    record,
                    last_op,
                    last_source: source,
                },
            );
        }
    }

    /// Reconcile local pending operations with remote operations.
    ///
    /// Returns the reconciliation result and the final record states.
    pub fn reconcile(
        mut self,
        local_ops: Vec<Operation>,
        remote_ops: Vec<Operation>,
    ) -> (ReconcileResult, HashMap<(CollectionName, RecordId), Record>) {
        // Track which local ops we've seen
        let local_op_ids: HashSet<_> = local_ops.iter().map(|op| op.op_id().clone()).collect();

        // Combine and sort all operations
        let mut all_ops: Vec<TrackedOp> = Vec::with_capacity(local_ops.len() + remote_ops.len());
        all_ops.extend(local_ops.into_iter().map(TrackedOp::local));
        all_ops.extend(remote_ops.into_iter().map(TrackedOp::remote));

        // Sort by (clock, timestamp, op_id) for deterministic total ordering
        all_ops.sort_by(|a, b| a.operation.cmp(&b.operation));

        // Apply operations in order
        for tracked in all_ops {
            self.apply_tracked_op(tracked, &local_op_ids);
        }

        // Extract final records
        let final_records: HashMap<_, _> = self
            .records
            .into_iter()
            .map(|(k, v)| (k, v.record))
            .collect();

        (self.result, final_records)
    }

    fn apply_tracked_op(&mut self, tracked: TrackedOp, local_op_ids: &HashSet<OperationId>) {
        let op = &tracked.operation;
        let key = (op.collection().clone(), op.record_id().clone());

        // Check for conflict with existing state
        if let Some(existing) = self.records.get(&key) {
            // Conflict: same record modified by different sources
            if self.is_conflict(&existing.last_op, op, existing.last_source, tracked.source) {
                self.handle_conflict(tracked, existing.clone(), local_op_ids);
                return;
            }
        }

        // No conflict - apply the operation
        self.apply_op_to_state(tracked, local_op_ids);
    }

    fn is_conflict(
        &self,
        _existing_op: &Operation,
        _new_op: &Operation,
        existing_source: OpSource,
        new_source: OpSource,
    ) -> bool {
        // Conflict if different sources are modifying the same record.
        // The merge strategy determines which one wins.
        existing_source != new_source
    }

    fn handle_conflict(
        &mut self,
        incoming: TrackedOp,
        existing: RecordState,
        _local_op_ids: &HashSet<OperationId>,
    ) {
        let (local_op, remote_op, local_source) = if incoming.source == OpSource::Local {
            (incoming.operation.clone(), existing.last_op.clone(), true)
        } else {
            (existing.last_op.clone(), incoming.operation.clone(), false)
        };

        // Determine winner based on strategy
        let (winner, resolution) = self.resolve_conflict(&local_op, &remote_op);

        let winner_op_id = winner.op_id().clone();
        let winner_is_local = winner.op_id() == local_op.op_id();

        // Record the conflict
        self.result.conflicts.push(Conflict {
            local_op: local_op.clone(),
            remote_op: remote_op.clone(),
            resolution: resolution.clone(),
            winner_op_id: winner_op_id.clone(),
        });

        // Update result tracking
        match resolution {
            ConflictResolution::LocalWins => {
                self.result.rejected_remote.push(remote_op.op_id().clone());
                // Local was already applied or will be kept
                if !self.result.accepted_local.contains(local_op.op_id()) {
                    self.result.accepted_local.push(local_op.op_id().clone());
                }
            }
            ConflictResolution::RemoteWins => {
                self.result.rejected_local.push(local_op.op_id().clone());
                self.result
                    .accepted_local
                    .retain(|id| id != local_op.op_id());
                if !self.result.applied_remote.contains(remote_op.op_id()) {
                    self.result.applied_remote.push(remote_op.op_id().clone());
                }
            }
        }

        // Apply winner if it's the incoming operation
        if (winner_is_local && local_source) || (!winner_is_local && !local_source) {
            // Incoming operation wins - apply it
            let tracked = TrackedOp {
                operation: winner,
                source: incoming.source,
            };
            self.force_apply_op(tracked);
        }
        // Otherwise, existing state remains (winner already applied)
    }

    fn resolve_conflict(
        &self,
        local_op: &Operation,
        remote_op: &Operation,
    ) -> (Operation, ConflictResolution) {
        match self.strategy {
            MergeStrategy::ClockWins => {
                // Compare by clock, then timestamp, then op_id
                if local_op >= remote_op {
                    (local_op.clone(), ConflictResolution::LocalWins)
                } else {
                    (remote_op.clone(), ConflictResolution::RemoteWins)
                }
            }
            MergeStrategy::TimestampWins => {
                if local_op.timestamp() >= remote_op.timestamp() {
                    (local_op.clone(), ConflictResolution::LocalWins)
                } else {
                    (remote_op.clone(), ConflictResolution::RemoteWins)
                }
            }
        }
    }

    fn apply_op_to_state(&mut self, tracked: TrackedOp, _local_op_ids: &HashSet<OperationId>) {
        let op_id = tracked.operation.op_id().clone();
        let source = tracked.source;

        // Track in result
        match source {
            OpSource::Local => {
                if !self.result.accepted_local.contains(&op_id) {
                    self.result.accepted_local.push(op_id.clone());
                }
            }
            OpSource::Remote => {
                if !self.result.applied_remote.contains(&op_id) {
                    self.result.applied_remote.push(op_id.clone());
                }
            }
        }

        self.force_apply_op(tracked);
    }

    fn force_apply_op(&mut self, tracked: TrackedOp) {
        let op = tracked.operation;
        let source = tracked.source;
        let key = (op.collection().clone(), op.record_id().clone());
        let origin = match source {
            OpSource::Local => Origin::Local,
            OpSource::Remote => Origin::Remote,
        };

        match &op {
            Operation::Create(create_op) => {
                let record = Record::new(
                    create_op.id.clone(),
                    create_op.collection.clone(),
                    create_op.payload.clone(),
                    create_op.timestamp,
                    create_op.clock.clone(),
                );
                self.records.insert(
                    key,
                    RecordState {
                        record,
                        last_op: op,
                        last_source: source,
                    },
                );
            }
            Operation::Update(update_op) => {
                if let Some(state) = self.records.get_mut(&key) {
                    state.record.update_payload(
                        update_op.payload.clone(),
                        update_op.timestamp,
                        update_op.clock.clone(),
                        origin,
                    );
                    state.last_op = op;
                    state.last_source = source;
                }
            }
            Operation::Delete(delete_op) => {
                if let Some(state) = self.records.get_mut(&key) {
                    state
                        .record
                        .mark_deleted(delete_op.timestamp, delete_op.clock.clone(), origin);
                    state.last_op = op;
                    state.last_source = source;
                }
            }
        }
    }

    /// Get current records (for inspection during reconciliation).
    pub fn current_records(&self) -> impl Iterator<Item = &Record> {
        self.records.values().map(|s| &s.record)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::operation::{CreateOp, UpdateOp};
    use crate::schema::{CollectionSchema, FieldDef, FieldType};
    use crate::LogicalClock;
    use serde_json::json;

    fn test_schema() -> Schema {
        Schema::new(1).with_collection(CollectionSchema::new(
            "users",
            vec![FieldDef::required("name", FieldType::String)],
        ))
    }

    #[test]
    fn reconcile_no_conflicts() {
        let schema = test_schema();
        let reconciler = Reconciler::new(&schema, MergeStrategy::ClockWins);

        // Local creates user-1, remote creates user-2
        let local_ops = vec![Operation::Create(CreateOp::new(
            "op-1",
            "user-1",
            "users",
            json!({"name": "Alice"}),
            1000,
            LogicalClock::with_counter("local", 1),
        ))];

        let remote_ops = vec![Operation::Create(CreateOp::new(
            "op-2",
            "user-2",
            "users",
            json!({"name": "Bob"}),
            1000,
            LogicalClock::with_counter("remote", 1),
        ))];

        let (result, records) = reconciler.reconcile(local_ops, remote_ops);

        assert_eq!(result.accepted_local.len(), 1);
        assert_eq!(result.applied_remote.len(), 1);
        assert_eq!(result.conflicts.len(), 0);
        assert_eq!(records.len(), 2);
    }

    #[test]
    fn reconcile_conflict_clock_wins_local() {
        let schema = test_schema();
        let reconciler = Reconciler::new(&schema, MergeStrategy::ClockWins);

        // Both try to create user-1, local has higher clock
        let local_ops = vec![Operation::Create(CreateOp::new(
            "op-local",
            "user-1",
            "users",
            json!({"name": "Alice"}),
            1000,
            LogicalClock::with_counter("local", 5), // higher counter
        ))];

        let remote_ops = vec![Operation::Create(CreateOp::new(
            "op-remote",
            "user-1",
            "users",
            json!({"name": "Bob"}),
            1000,
            LogicalClock::with_counter("remote", 3), // lower counter
        ))];

        let (result, records) = reconciler.reconcile(local_ops, remote_ops);

        assert_eq!(result.conflicts.len(), 1);
        assert_eq!(
            result.conflicts[0].resolution,
            ConflictResolution::LocalWins
        );
        assert_eq!(result.accepted_local, vec!["op-local".to_string()]);
        assert_eq!(result.rejected_remote, vec!["op-remote".to_string()]);

        // Record should have Alice (local won)
        let record = records
            .get(&("users".to_string(), "user-1".to_string()))
            .unwrap();
        assert_eq!(record.payload, json!({"name": "Alice"}));
    }

    #[test]
    fn reconcile_conflict_clock_wins_remote() {
        let schema = test_schema();
        let reconciler = Reconciler::new(&schema, MergeStrategy::ClockWins);

        // Both try to create user-1, remote has higher clock
        let local_ops = vec![Operation::Create(CreateOp::new(
            "op-local",
            "user-1",
            "users",
            json!({"name": "Alice"}),
            1000,
            LogicalClock::with_counter("local", 2), // lower counter
        ))];

        let remote_ops = vec![Operation::Create(CreateOp::new(
            "op-remote",
            "user-1",
            "users",
            json!({"name": "Bob"}),
            1000,
            LogicalClock::with_counter("remote", 5), // higher counter
        ))];

        let (result, records) = reconciler.reconcile(local_ops, remote_ops);

        assert_eq!(result.conflicts.len(), 1);
        assert_eq!(
            result.conflicts[0].resolution,
            ConflictResolution::RemoteWins
        );
        assert_eq!(result.rejected_local, vec!["op-local".to_string()]);
        assert_eq!(result.applied_remote, vec!["op-remote".to_string()]);

        // Record should have Bob (remote won)
        let record = records
            .get(&("users".to_string(), "user-1".to_string()))
            .unwrap();
        assert_eq!(record.payload, json!({"name": "Bob"}));
    }

    #[test]
    fn reconcile_conflict_same_clock_node_id_tiebreak() {
        let schema = test_schema();
        let reconciler = Reconciler::new(&schema, MergeStrategy::ClockWins);

        // Same counter, node_id breaks tie ("remote" > "local" lexicographically)
        let local_ops = vec![Operation::Create(CreateOp::new(
            "op-local",
            "user-1",
            "users",
            json!({"name": "Alice"}),
            1000,
            LogicalClock::with_counter("local", 5),
        ))];

        let remote_ops = vec![Operation::Create(CreateOp::new(
            "op-remote",
            "user-1",
            "users",
            json!({"name": "Bob"}),
            1000,
            LogicalClock::with_counter("remote", 5), // same counter, but "remote" > "local"
        ))];

        let (result, records) = reconciler.reconcile(local_ops, remote_ops);

        assert_eq!(result.conflicts.len(), 1);
        // "remote" > "local" lexicographically, so remote wins
        assert_eq!(
            result.conflicts[0].resolution,
            ConflictResolution::RemoteWins
        );

        let record = records
            .get(&("users".to_string(), "user-1".to_string()))
            .unwrap();
        assert_eq!(record.payload, json!({"name": "Bob"}));
    }

    #[test]
    fn reconcile_update_conflict() {
        let schema = test_schema();
        let mut reconciler = Reconciler::new(&schema, MergeStrategy::ClockWins);

        // Pre-existing record
        let existing = Record::new(
            "user-1",
            "users",
            json!({"name": "Original"}),
            500,
            LogicalClock::with_counter("server", 1),
        );
        let create_op = Operation::Create(CreateOp::new(
            "op-0",
            "user-1",
            "users",
            json!({"name": "Original"}),
            500,
            LogicalClock::with_counter("server", 1),
        ));
        reconciler.load_records(std::iter::once((existing, create_op, OpSource::Remote)));

        // Both try to update
        let local_ops = vec![Operation::Update(UpdateOp::new(
            "op-local",
            "user-1",
            "users",
            json!({"name": "Alice Update"}),
            1,
            1000,
            LogicalClock::with_counter("local", 10),
        ))];

        let remote_ops = vec![Operation::Update(UpdateOp::new(
            "op-remote",
            "user-1",
            "users",
            json!({"name": "Bob Update"}),
            1,
            1000,
            LogicalClock::with_counter("remote", 5),
        ))];

        let (result, records) = reconciler.reconcile(local_ops, remote_ops);

        assert_eq!(result.conflicts.len(), 1);
        assert_eq!(
            result.conflicts[0].resolution,
            ConflictResolution::LocalWins
        );

        let record = records
            .get(&("users".to_string(), "user-1".to_string()))
            .unwrap();
        assert_eq!(record.payload, json!({"name": "Alice Update"}));
    }

    #[test]
    fn reconcile_timestamp_strategy() {
        let schema = test_schema();
        let reconciler = Reconciler::new(&schema, MergeStrategy::TimestampWins);

        // Local has lower clock but higher timestamp
        let local_ops = vec![Operation::Create(CreateOp::new(
            "op-local",
            "user-1",
            "users",
            json!({"name": "Alice"}),
            2000, // higher timestamp
            LogicalClock::with_counter("local", 1),
        ))];

        let remote_ops = vec![Operation::Create(CreateOp::new(
            "op-remote",
            "user-1",
            "users",
            json!({"name": "Bob"}),
            1000, // lower timestamp
            LogicalClock::with_counter("remote", 5),
        ))];

        let (result, records) = reconciler.reconcile(local_ops, remote_ops);

        assert_eq!(result.conflicts.len(), 1);
        // With TimestampWins, local wins due to higher timestamp
        assert_eq!(
            result.conflicts[0].resolution,
            ConflictResolution::LocalWins
        );

        let record = records
            .get(&("users".to_string(), "user-1".to_string()))
            .unwrap();
        assert_eq!(record.payload, json!({"name": "Alice"}));
    }

    #[test]
    fn reconcile_deterministic() {
        let schema = test_schema();

        let local_ops = vec![Operation::Create(CreateOp::new(
            "op-local",
            "user-1",
            "users",
            json!({"name": "Alice"}),
            1000,
            LogicalClock::with_counter("local", 3),
        ))];

        let remote_ops = vec![Operation::Create(CreateOp::new(
            "op-remote",
            "user-1",
            "users",
            json!({"name": "Bob"}),
            1000,
            LogicalClock::with_counter("remote", 3),
        ))];

        // Run reconciliation multiple times
        let mut results = Vec::new();
        for _ in 0..10 {
            let reconciler = Reconciler::new(&schema, MergeStrategy::ClockWins);
            let (_result, records) = reconciler.reconcile(local_ops.clone(), remote_ops.clone());
            let winner = records
                .get(&("users".to_string(), "user-1".to_string()))
                .unwrap()
                .payload
                .clone();
            results.push(winner);
        }

        // All results should be identical
        assert!(results.windows(2).all(|w| w[0] == w[1]));
    }

    #[test]
    fn reconcile_multiple_records_mixed() {
        let schema = test_schema();
        let reconciler = Reconciler::new(&schema, MergeStrategy::ClockWins);

        let local_ops = vec![
            Operation::Create(CreateOp::new(
                "op-l1",
                "user-1",
                "users",
                json!({"name": "Alice"}),
                1000,
                LogicalClock::with_counter("local", 1),
            )),
            Operation::Create(CreateOp::new(
                "op-l2",
                "user-2",
                "users",
                json!({"name": "Charlie"}),
                1000,
                LogicalClock::with_counter("local", 2),
            )),
        ];

        let remote_ops = vec![
            Operation::Create(CreateOp::new(
                "op-r1",
                "user-1",
                "users",
                json!({"name": "Bob"}),
                1000,
                LogicalClock::with_counter("remote", 5), // wins user-1
            )),
            Operation::Create(CreateOp::new(
                "op-r2",
                "user-3",
                "users",
                json!({"name": "Dave"}),
                1000,
                LogicalClock::with_counter("remote", 1),
            )),
        ];

        let (result, records) = reconciler.reconcile(local_ops, remote_ops);

        // user-1: conflict, remote wins (higher clock)
        // user-2: no conflict, local accepted
        // user-3: no conflict, remote applied
        assert_eq!(result.conflicts.len(), 1);
        assert_eq!(records.len(), 3);

        assert_eq!(
            records
                .get(&("users".to_string(), "user-1".to_string()))
                .unwrap()
                .payload,
            json!({"name": "Bob"})
        );
        assert_eq!(
            records
                .get(&("users".to_string(), "user-2".to_string()))
                .unwrap()
                .payload,
            json!({"name": "Charlie"})
        );
        assert_eq!(
            records
                .get(&("users".to_string(), "user-3".to_string()))
                .unwrap()
                .payload,
            json!({"name": "Dave"})
        );
    }

    // Property-based tests using proptest
    mod property_tests {
        use super::*;
        use crate::LogicalClock;
        use proptest::prelude::*;

        #[allow(dead_code)]
        fn arb_node_id() -> impl Strategy<Value = String> {
            prop_oneof![Just("local".to_string()), Just("remote".to_string()),]
        }

        #[allow(dead_code)]
        fn arb_clock(node_id: String) -> impl Strategy<Value = LogicalClock> {
            (1u64..100)
                .prop_map(move |counter| LogicalClock::with_counter(node_id.clone(), counter))
        }

        #[allow(dead_code)]
        fn arb_create_op(op_id: String, record_id: String) -> impl Strategy<Value = Operation> {
            (arb_node_id(), 1u64..100, 1000u64..5000).prop_flat_map(
                move |(node_id, counter, timestamp)| {
                    let op_id = op_id.clone();
                    let record_id = record_id.clone();
                    Just(Operation::Create(CreateOp::new(
                        op_id,
                        record_id,
                        "users",
                        json!({"name": "Test"}),
                        timestamp,
                        LogicalClock::with_counter(node_id, counter),
                    )))
                },
            )
        }

        proptest! {
            #[test]
            fn prop_reconcile_deterministic(
                local_counter in 1u64..100,
                remote_counter in 1u64..100,
                local_timestamp in 1000u64..5000,
                remote_timestamp in 1000u64..5000,
            ) {
                let schema = test_schema();

                let local_ops = vec![Operation::Create(CreateOp::new(
                    "op-local",
                    "user-1",
                    "users",
                    json!({"name": "Alice"}),
                    local_timestamp,
                    LogicalClock::with_counter("local", local_counter),
                ))];

                let remote_ops = vec![Operation::Create(CreateOp::new(
                    "op-remote",
                    "user-1",
                    "users",
                    json!({"name": "Bob"}),
                    remote_timestamp,
                    LogicalClock::with_counter("remote", remote_counter),
                ))];

                // Run reconciliation twice
                let reconciler1 = Reconciler::new(&schema, MergeStrategy::ClockWins);
                let (_, records1) = reconciler1.reconcile(local_ops.clone(), remote_ops.clone());

                let reconciler2 = Reconciler::new(&schema, MergeStrategy::ClockWins);
                let (_, records2) = reconciler2.reconcile(local_ops, remote_ops);

                // Results must be identical
                let payload1 = &records1.get(&("users".to_string(), "user-1".to_string())).unwrap().payload;
                let payload2 = &records2.get(&("users".to_string(), "user-1".to_string())).unwrap().payload;
                prop_assert_eq!(payload1, payload2);
            }

            #[test]
            fn prop_reconcile_symmetric(
                local_counter in 1u64..100,
                remote_counter in 1u64..100,
            ) {
                // Two stores starting from same state, receiving each other's ops,
                // should end up with identical state
                let schema = test_schema();

                let local_op = Operation::Create(CreateOp::new(
                    "op-local",
                    "user-1",
                    "users",
                    json!({"name": "Alice"}),
                    1000,
                    LogicalClock::with_counter("local", local_counter),
                ));

                let remote_op = Operation::Create(CreateOp::new(
                    "op-remote",
                    "user-1",
                    "users",
                    json!({"name": "Bob"}),
                    1000,
                    LogicalClock::with_counter("remote", remote_counter),
                ));

                // Store A: has local_op, receives remote_op
                let reconciler_a = Reconciler::new(&schema, MergeStrategy::ClockWins);
                let (_, records_a) = reconciler_a.reconcile(vec![local_op.clone()], vec![remote_op.clone()]);

                // Store B: has remote_op, receives local_op
                let reconciler_b = Reconciler::new(&schema, MergeStrategy::ClockWins);
                let (_, records_b) = reconciler_b.reconcile(vec![remote_op], vec![local_op]);

                // Both should have identical final state
                let payload_a = &records_a.get(&("users".to_string(), "user-1".to_string())).unwrap().payload;
                let payload_b = &records_b.get(&("users".to_string(), "user-1".to_string())).unwrap().payload;
                prop_assert_eq!(payload_a, payload_b);
            }

            #[test]
            fn prop_no_data_loss_without_conflict(
                local_counter in 1u64..100,
                remote_counter in 1u64..100,
            ) {
                // When records don't conflict, all should be present
                let schema = test_schema();

                let local_ops = vec![Operation::Create(CreateOp::new(
                    "op-local",
                    "user-1", // different record
                    "users",
                    json!({"name": "Alice"}),
                    1000,
                    LogicalClock::with_counter("local", local_counter),
                ))];

                let remote_ops = vec![Operation::Create(CreateOp::new(
                    "op-remote",
                    "user-2", // different record
                    "users",
                    json!({"name": "Bob"}),
                    1000,
                    LogicalClock::with_counter("remote", remote_counter),
                ))];

                let reconciler = Reconciler::new(&schema, MergeStrategy::ClockWins);
                let (result, records) = reconciler.reconcile(local_ops, remote_ops);

                // No conflicts
                prop_assert_eq!(result.conflicts.len(), 0);

                // Both records present
                prop_assert!(records.contains_key(&("users".to_string(), "user-1".to_string())));
                prop_assert!(records.contains_key(&("users".to_string(), "user-2".to_string())));
            }
        }
    }
}
