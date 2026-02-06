//! Record types for storing data.

use crate::{CollectionName, LogicalClock, RecordId, Timestamp, Version};
use serde::{Deserialize, Serialize};

/// Origin of a record or operation.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Origin {
    /// Created or modified locally
    Local,
    /// Received from remote/server
    Remote,
}

/// Metadata associated with a record.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Metadata {
    /// When the record was first created (milliseconds since epoch)
    pub created_at: Timestamp,
    /// When the record was last updated (milliseconds since epoch)
    pub updated_at: Timestamp,
    /// Whether this record originated locally or from remote
    pub origin: Origin,
    /// Logical clock at the time of last update
    pub clock: LogicalClock,
}

impl Metadata {
    /// Create new metadata for a locally created record.
    pub fn new_local(timestamp: Timestamp, clock: LogicalClock) -> Self {
        Self {
            created_at: timestamp,
            updated_at: timestamp,
            origin: Origin::Local,
            clock,
        }
    }

    /// Create new metadata for a remotely received record.
    pub fn new_remote(timestamp: Timestamp, clock: LogicalClock) -> Self {
        Self {
            created_at: timestamp,
            updated_at: timestamp,
            origin: Origin::Remote,
            clock,
        }
    }

    /// Update metadata for a modification.
    pub fn update(&mut self, timestamp: Timestamp, clock: LogicalClock, origin: Origin) {
        self.updated_at = timestamp;
        self.clock = clock;
        self.origin = origin;
    }
}

/// A data record in the store.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Record {
    /// Unique identifier for this record
    pub id: RecordId,
    /// Collection this record belongs to
    pub collection: CollectionName,
    /// Version number, incremented on each update
    pub version: Version,
    /// The actual data payload (JSON value)
    pub payload: serde_json::Value,
    /// Record metadata
    pub metadata: Metadata,
    /// Soft delete flag (tombstone)
    pub deleted: bool,
}

impl Record {
    /// Create a new record.
    pub fn new(
        id: impl Into<RecordId>,
        collection: impl Into<CollectionName>,
        payload: serde_json::Value,
        timestamp: Timestamp,
        clock: LogicalClock,
    ) -> Self {
        Self {
            id: id.into(),
            collection: collection.into(),
            version: 1,
            payload,
            metadata: Metadata::new_local(timestamp, clock),
            deleted: false,
        }
    }

    /// Check if record is active (not deleted).
    pub fn is_active(&self) -> bool {
        !self.deleted
    }

    /// Mark record as deleted (tombstone).
    pub fn mark_deleted(&mut self, timestamp: Timestamp, clock: LogicalClock, origin: Origin) {
        self.deleted = true;
        self.version += 1;
        self.metadata.update(timestamp, clock, origin);
    }

    /// Update record payload.
    pub fn update_payload(
        &mut self,
        payload: serde_json::Value,
        timestamp: Timestamp,
        clock: LogicalClock,
        origin: Origin,
    ) {
        self.payload = payload;
        self.version += 1;
        self.metadata.update(timestamp, clock, origin);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn create_record() {
        let clock = LogicalClock::with_counter("node-1", 1);
        let record = Record::new("user-1", "users", json!({"name": "Alice"}), 1000, clock);

        assert_eq!(record.id, "user-1");
        assert_eq!(record.collection, "users");
        assert_eq!(record.version, 1);
        assert_eq!(record.payload, json!({"name": "Alice"}));
        assert!(!record.deleted);
        assert!(record.is_active());
    }

    #[test]
    fn update_record() {
        let clock = LogicalClock::with_counter("node-1", 1);
        let mut record = Record::new("user-1", "users", json!({"name": "Alice"}), 1000, clock);

        let new_clock = LogicalClock::with_counter("node-1", 2);
        record.update_payload(
            json!({"name": "Alice Smith"}),
            2000,
            new_clock,
            Origin::Local,
        );

        assert_eq!(record.version, 2);
        assert_eq!(record.payload, json!({"name": "Alice Smith"}));
        assert_eq!(record.metadata.updated_at, 2000);
    }

    #[test]
    fn delete_record() {
        let clock = LogicalClock::with_counter("node-1", 1);
        let mut record = Record::new("user-1", "users", json!({"name": "Alice"}), 1000, clock);

        let delete_clock = LogicalClock::with_counter("node-1", 2);
        record.mark_deleted(2000, delete_clock, Origin::Local);

        assert!(record.deleted);
        assert!(!record.is_active());
        assert_eq!(record.version, 2);
    }

    #[test]
    fn metadata_origin() {
        let clock = LogicalClock::with_counter("node-1", 1);

        let local = Metadata::new_local(1000, clock.clone());
        assert_eq!(local.origin, Origin::Local);

        let remote = Metadata::new_remote(1000, clock);
        assert_eq!(remote.origin, Origin::Remote);
    }

    #[test]
    fn serialization_roundtrip() {
        let clock = LogicalClock::with_counter("node-1", 1);
        let record = Record::new(
            "user-1",
            "users",
            json!({"name": "Alice", "age": 30}),
            1000,
            clock,
        );

        let json = serde_json::to_string(&record).unwrap();
        let parsed: Record = serde_json::from_str(&json).unwrap();

        assert_eq!(record, parsed);
    }
}
