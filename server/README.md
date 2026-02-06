# Carry Server

A sync server for local-first data synchronization, powered by the Carry engine.

## Features

- **Deterministic sync**: Uses the same `carry-engine` reconciliation logic as clients
- **PostgreSQL persistence**: Durable storage with append-only operation log
- **Conflict resolution**: Automatic conflict handling using logical clocks
- **RESTful API**: Simple HTTP endpoints for push/pull sync

## Requirements

- Rust 1.70+
- PostgreSQL 14+

## Setup

Copy the example environment file:

```bash
cp .env.example .env
```

Configure your database URL in `.env`:

```bash
DATABASE_URL=postgres://user:password@localhost:5432/carry
```

Create the database:

```bash
createdb carry
```

Run the server:

```bash
cargo run --release
```

The server will automatically run migrations on startup.

## API Endpoints

### Health Check

```bash
GET /health
```

Response:

```json
{
  "status": "ok",
  "version": "0.1.0"
}
```

### Push Operations

```bash
POST /sync
Authorization: Bearer <token>
Content-Type: application/json

{
  "nodeId": "device_abc123",
  "operations": [
    {
      "type": "create",
      "opId": "op-1",
      "id": "record-1",
      "collection": "todos",
      "payload": {"title": "Buy milk"},
      "timestamp": 1706745600000,
      "clock": {"nodeId": "device_abc123", "counter": 1}
    }
  ]
}
```

Response:

```json
{
  "accepted": ["op-1"],
  "rejected": [],
  "serverClock": 42
}
```

### Pull Operations

```bash
GET /sync?since=<sync_token>&limit=100
Authorization: Bearer <token>
```

Response:

```json
{
  "operations": [...],
  "syncToken": "1706745600000_op-42",
  "hasMore": false
}
```

## Configuration

| Variable       | Description                 | Default    |
| -------------- | --------------------------- | ---------- |
| `HOST`         | Server bind address         | `0.0.0.0`  |
| `PORT`         | Server port                 | `3000`     |
| `DATABASE_URL` | PostgreSQL connection URL   | (required) |
| `AUTH_SECRET`  | Secret for token validation | (optional) |

## Development

Run tests:

```bash
cargo test
```

Run with logging:

```bash
RUST_LOG=carry_server=debug cargo run
```

## Architecture

```plain
┌─────────────────────────────────┐
│         carry-server            │
│  ┌───────────────────────────┐  │
│  │   HTTP Layer (axum)       │  │
│  │   /sync endpoints         │  │
│  └───────────┬───────────────┘  │
│              │                  │
│  ┌───────────▼───────────────┐  │
│  │   carry-engine (crate)    │  │
│  │   Store, Reconcile, etc.  │  │
│  └───────────┬───────────────┘  │
│              │                  │
│  ┌───────────▼───────────────┐  │
│  │   Persistence (Postgres)  │  │
│  └───────────────────────────┘  │
└─────────────────────────────────┘
```

## License

MIT
