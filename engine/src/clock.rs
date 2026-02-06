//! Logical clock for causal ordering of operations.
//!
//! The clock provides a total ordering across all nodes, which is essential
//! for deterministic conflict resolution.

use crate::NodeId;
use serde::{Deserialize, Serialize};
use std::cmp::Ordering;

/// A logical clock that provides causal ordering.
///
/// Ordering rules:
/// 1. Higher counter wins
/// 2. If counters equal, lexicographically higher node_id wins
///
/// This ensures a total order across all operations from all nodes.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LogicalClock {
    /// Unique identifier for the node (client or server instance)
    pub node_id: NodeId,
    /// Monotonically increasing counter
    pub counter: u64,
}

impl LogicalClock {
    /// Create a new clock for a node, starting at counter 0.
    pub fn new(node_id: impl Into<NodeId>) -> Self {
        Self {
            node_id: node_id.into(),
            counter: 0,
        }
    }

    /// Create a clock with a specific counter value.
    pub fn with_counter(node_id: impl Into<NodeId>, counter: u64) -> Self {
        Self {
            node_id: node_id.into(),
            counter,
        }
    }

    /// Increment the clock and return the new value.
    pub fn tick(&mut self) -> &Self {
        self.counter += 1;
        self
    }

    /// Update this clock to be at least as recent as another clock.
    /// Used when receiving remote operations.
    pub fn merge(&mut self, other: &LogicalClock) {
        self.counter = self.counter.max(other.counter);
    }

    /// Check if this clock happened before another (strict causal ordering).
    /// Returns true only if this clock is strictly less than other.
    pub fn happened_before(&self, other: &LogicalClock) -> bool {
        self.counter < other.counter
    }

    /// Check if two clocks are concurrent (neither happened before the other
    /// based on counter alone, but from different nodes).
    pub fn is_concurrent_with(&self, other: &LogicalClock) -> bool {
        self.counter == other.counter && self.node_id != other.node_id
    }
}

impl Ord for LogicalClock {
    fn cmp(&self, other: &Self) -> Ordering {
        match self.counter.cmp(&other.counter) {
            Ordering::Equal => self.node_id.cmp(&other.node_id),
            other => other,
        }
    }
}

impl PartialOrd for LogicalClock {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn new_clock_starts_at_zero() {
        let clock = LogicalClock::new("node-1");
        assert_eq!(clock.counter, 0);
        assert_eq!(clock.node_id, "node-1");
    }

    #[test]
    fn tick_increments_counter() {
        let mut clock = LogicalClock::new("node-1");
        clock.tick();
        assert_eq!(clock.counter, 1);
        clock.tick();
        assert_eq!(clock.counter, 2);
    }

    #[test]
    fn ordering_by_counter() {
        let clock1 = LogicalClock::with_counter("node-a", 1);
        let clock2 = LogicalClock::with_counter("node-b", 2);
        assert!(clock1 < clock2);
    }

    #[test]
    fn ordering_by_node_id_when_counter_equal() {
        let clock_a = LogicalClock::with_counter("node-a", 5);
        let clock_b = LogicalClock::with_counter("node-b", 5);
        assert!(clock_a < clock_b); // "node-a" < "node-b" lexicographically
    }

    #[test]
    fn merge_takes_max_counter() {
        let mut clock1 = LogicalClock::with_counter("node-1", 3);
        let clock2 = LogicalClock::with_counter("node-2", 7);
        clock1.merge(&clock2);
        assert_eq!(clock1.counter, 7);
        assert_eq!(clock1.node_id, "node-1"); // node_id unchanged
    }

    #[test]
    fn merge_keeps_higher_counter() {
        let mut clock1 = LogicalClock::with_counter("node-1", 10);
        let clock2 = LogicalClock::with_counter("node-2", 5);
        clock1.merge(&clock2);
        assert_eq!(clock1.counter, 10);
    }

    #[test]
    fn happened_before() {
        let clock1 = LogicalClock::with_counter("node-1", 1);
        let clock2 = LogicalClock::with_counter("node-2", 2);
        assert!(clock1.happened_before(&clock2));
        assert!(!clock2.happened_before(&clock1));
    }

    #[test]
    fn is_concurrent() {
        let clock1 = LogicalClock::with_counter("node-1", 5);
        let clock2 = LogicalClock::with_counter("node-2", 5);
        assert!(clock1.is_concurrent_with(&clock2));

        let clock3 = LogicalClock::with_counter("node-1", 5);
        assert!(!clock1.is_concurrent_with(&clock3)); // same node
    }

    #[test]
    fn serialization_roundtrip() {
        let clock = LogicalClock::with_counter("node-123", 42);
        let json = serde_json::to_string(&clock).unwrap();
        let parsed: LogicalClock = serde_json::from_str(&json).unwrap();
        assert_eq!(clock, parsed);
    }

    #[test]
    fn serialization_format() {
        let clock = LogicalClock::with_counter("node-1", 10);
        let json = serde_json::to_string(&clock).unwrap();
        assert!(json.contains("nodeId")); // camelCase
        assert!(json.contains("counter"));
    }
}
