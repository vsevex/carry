//! WebSocket support for real-time sync.
//!
//! This module provides WebSocket-based sync as an alternative to HTTP polling.
//! Clients connect via WebSocket and receive push notifications when new operations
//! arrive from other clients.

mod manager;
mod protocol;

pub use manager::ConnectionManager;
pub use protocol::*;
