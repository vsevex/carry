//! # Carry Engine
//!
//! A deterministic sync engine for local-first applications.
//!
//! This crate provides the core logic for offline-first data synchronization.
//! It handles records, operations, conflict resolution, and state reconciliation
//! with guaranteed determinism - the same inputs always produce the same outputs.
//!
//! ## Design Principles
//!
//! - **No IO**: Engine has no knowledge of files, network, or platform
//! - **Deterministic**: Same inputs always produce same outputs
//! - **Testable**: Pure logic, no mocks needed
//! - **Portable**: Runs anywhere Rust runs (native, WASM, embedded)
//!
//! ## Core Concepts
//!
//! ### Records
//!
//! Data is stored as records with:
//! - Unique ID
//! - Collection membership
//! - Version number (for optimistic concurrency)
//! - JSON payload
//! - Metadata (timestamps, origin, logical clock)
//! - Soft delete flag (tombstone)
//!
//! ### Operations
//!
//! Changes are expressed as operations, not direct mutations:
//! - [`CreateOp`] - Create a new record
//! - [`UpdateOp`] - Update an existing record (version checked)
//! - [`DeleteOp`] - Soft-delete a record (tombstone)
//!
//! ### Logical Clock
//!
//! The [`LogicalClock`] provides causal ordering across distributed nodes.
//! It combines a counter with a node ID for total ordering.
//!
//! ### Reconciliation
//!
//! The [`Reconciler`] merges local and remote operations deterministically.
//! Conflicts are resolved using configurable strategies:
//! - [`MergeStrategy::ClockWins`] - Higher logical clock wins (default)
//! - [`MergeStrategy::TimestampWins`] - Higher timestamp wins
//!
//! ## Quick Start
//!
//! ```rust
//! use carry_engine::{
//!     Schema, CollectionSchema, FieldDef, FieldType,
//!     Store, Operation, CreateOp, LogicalClock,
//! };
//! use serde_json::json;
//!
//! // 1. Define a schema
//! let mut schema = Schema::new(1);
//! let fields = vec![
//!     FieldDef::required("name", FieldType::String),
//!     FieldDef::optional("email", FieldType::String),
//! ];
//! schema.add_collection(CollectionSchema::new("users", fields));
//!
//! // 2. Create a store
//! let mut store = Store::new(schema, "device_1".to_string());
//!
//! // 3. Apply operations
//! let op = Operation::Create(CreateOp::new(
//!     "op_1",
//!     "user_1",
//!     "users",
//!     json!({"name": "Alice", "email": "alice@example.com"}),
//!     1706745600000, // timestamp
//!     LogicalClock::with_counter("device_1", 1),
//! ));
//!
//! let result = store.apply(op, 1706745600000).unwrap();
//! assert_eq!(result.record_id, "user_1");
//!
//! // 4. Query records
//! let records = store.query("users").unwrap().all();
//! assert_eq!(records.len(), 1);
//! ```
//!
//! ## FFI
//!
//! The [`ffi`] module provides C-compatible functions for use from other languages
//! (Dart/Flutter, Swift, Kotlin, etc.). All data is exchanged as JSON strings.
//!
//! ## Persistence
//!
//! Use [`Store::export_state`] and [`Store::import_state`] with [`StoreSnapshot`]
//! for persistence. Snapshots are serializable to JSON with deterministic ordering.

pub mod clock;
pub mod error;
pub mod ffi;
pub mod operation;
pub mod reconcile;
pub mod record;
pub mod schema;
pub mod snapshot;
pub mod store;

// Re-export main types at crate root
pub use clock::LogicalClock;
pub use error::Error;
pub use operation::{CreateOp, DeleteOp, Operation, OperationId, UpdateOp};
pub use reconcile::{
    Conflict, ConflictResolution, MergeStrategy, OpSource, ReconcileResult, Reconciler,
};
pub use record::{Metadata, Origin, Record};
pub use schema::{CollectionSchema, FieldDef, FieldType, Schema};
pub use snapshot::{SnapshotMetadata, StoreSnapshot, SNAPSHOT_FORMAT_VERSION};
pub use store::{ApplyResult, Collection, PendingOp, QueryBuilder, Store};

/// Type aliases for clarity
pub type RecordId = String;
pub type CollectionName = String;
pub type NodeId = String;
pub type Version = u64;
pub type Timestamp = u64;
pub type SchemaVersion = u32;
