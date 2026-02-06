# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-02-06

### Added

- **Core SDK**
  - `SyncStore` - Main entry point for offline-first data management
  - `Collection<T>` - Typed collection API with CRUD operations
  - `Schema` - Fluent schema builder for defining collections and fields
  - `Field` - Support for string, int, float, bool, timestamp, and JSON field types

- **Operations & Sync**
  - `CreateOp`, `UpdateOp`, `DeleteOp` - Operation types for data changes
  - `LogicalClock` - Hybrid logical clock for causal ordering
  - Automatic conflict resolution with configurable merge strategies
  - Pull-reconcile-push sync cycle

- **Persistence**
  - `PersistenceAdapter` - Interface for custom storage backends
  - `FilePersistenceAdapter` - File-based persistence implementation
  - Automatic state persistence and recovery

- **Transport**
  - `Transport` - Interface for custom server communication
  - `HttpTransport` - HTTP-based sync transport with configurable endpoints
  - Support for custom headers and authentication

- **Hooks**
  - `StoreHooks` - Lifecycle hooks for operations and sync events
  - `beforeInsert`, `afterInsert`, `beforeUpdate`, `afterUpdate`, `beforeDelete`, `afterDelete`
  - `beforeSync`, `afterSync`, `onSyncError`, `onConflict`

- **Native Engine**
  - Rust-powered CRDT engine via FFI
  - Deterministic conflict resolution
  - Efficient snapshot import/export

### Fixed

- Sync now correctly pushes pending operations (operations were being cleared before push)
- Store initialization race condition in async contexts

## [0.0.1] - 2026-02-01

- Initial project structure
- Basic FFI bindings to Rust engine
