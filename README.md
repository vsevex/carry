# Carry

A local-first data cache and sync layer for Flutter apps, powered by a deterministic Rust core.

## Why Carry?

- Your Flutter app works offline by default
- Your app feels fast even on bad networks
- You don't write cache, retry, merge, or sync logic
- Client and backend never disagree
- You can start simple and grow safely

## Architecture

Three layers with strict boundaries:

```plain
┌─────────────────────────────────────┐
│          Flutter SDK                │  ← Developer Interface
│   (API, persistence, transport)     │
├─────────────────────────────────────┤
│            Rust Core                │  ← Truth Engine
│   (model, merge, sync, validation)  │
├─────────────────────────────────────┤
│     Optional Backend Runtime        │  ← Coordinator
│       (same Rust logic)             │
└─────────────────────────────────────┘
```

## Core Concepts

### Records

Data is stored as records:

```plain
id         → string
version    → revision number
payload    → JSON-like data
metadata   → timestamps, source
```

No ORM. Flat and explicit.

### Operations, Not Mutations

Changes are expressed as operations, not overwrites:

- `create`
- `update`
- `delete`

Operations are logged locally and reconciled later. This is what enables offline-first behavior.

### Deterministic Merge

Given local state, remote state, and operation history, the Rust core always produces the same result. No "last write wins" magic unless explicitly configured.

### Sync Flow

```plain
1. Load local state
2. Fetch remote changes
3. Reconcile deterministically  ← Rust controls this
4. Apply results locally
5. Push accepted ops back
```

Rust controls the logic. Flutter handles transport.

## Flutter SDK (Preview)

```dart
final store = SyncStore(
  schema: UserSchema(),
  transport: HttpTransport(baseUrl: "..."),
);

await store.init();

final users = store.collection<User>("users");

users.insert(User(id: "1", name: "Alice"));

final list = users.query().all();
```

No manual caching. No manual retries. No manual offline checks.

## Rust Core API (Conceptual)

```rust
init_store()
apply_operation()
reconcile(remote_ops)
get_state()
export_pending_ops()
```

No IO. No HTTP. No platform knowledge. Testable without Flutter.

## Role Boundaries

### Rust Core

Rust is for determinism and safety, not just speed.

Responsibilities:

- Canonical data model
- Local cache representation
- Diff calculation
- Merge / conflict resolution
- Sync protocol rules
- Validation & invariants
- Versioned behavior

Rust produces decisions, not UI or IO.

### Flutter SDK (Non-negotiable)

Flutter is the primary consumer of the system.

Responsibilities:

- API surface for developers
- Local persistence (file/db wiring)
- Network transport (HTTP, WebSocket later)
- UI reactivity
- Platform abstraction

Flutter never:

- Decides merge rules
- Decides validity
- Invents state

Flutter asks Rust: "what is the state now?"

## v1 Scope

### Must-have

| Feature            | Description                                  |
| ------------------ | -------------------------------------------- |
| Local cache        | Persistent, queryable, offline-first         |
| Deterministic sync | Same result on client and server, idempotent |
| Conflict handling  | Default strategy, pluggable strategies later |
| Versioned schema   | Explicit migrations, no silent changes       |
| Flutter-first DX   | Simple API, few concepts, hard to misuse     |

### Explicitly NOT in v1

- Realtime sync
- Auth
- Permissions
- Encryption
- Background jobs
- Push notifications
- Admin UI

These come later or never.

## Maintenance Philosophy

### Version Everything

- Schema
- Operations
- Sync protocol
- Rust core

Never "just change behavior".

### Backward Compatibility > Features

If a new feature risks breaking old data: delay it or version it. Never "fix forward" silently.

### Test Invariants

Critical invariants:

- Offline → online consistency
- Client == server result
- Idempotent sync
- No data loss

## License

MIT
