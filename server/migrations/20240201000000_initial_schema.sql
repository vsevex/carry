-- Initial database schema for Carry Server

-- Operations log (append-only)
-- This is the source of truth for all changes
CREATE TABLE IF NOT EXISTS operations (
    id SERIAL PRIMARY KEY,
    op_id TEXT UNIQUE NOT NULL,
    node_id TEXT NOT NULL,
    collection TEXT NOT NULL,
    record_id TEXT NOT NULL,
    op_type TEXT NOT NULL,  -- 'create', 'update', 'delete'
    payload JSONB,
    clock_counter BIGINT NOT NULL,
    clock_node_id TEXT NOT NULL,
    timestamp BIGINT NOT NULL,
    base_version BIGINT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for efficient querying
CREATE INDEX IF NOT EXISTS idx_ops_timestamp ON operations(timestamp);
CREATE INDEX IF NOT EXISTS idx_ops_timestamp_opid ON operations(timestamp, op_id);
CREATE INDEX IF NOT EXISTS idx_ops_collection ON operations(collection);
CREATE INDEX IF NOT EXISTS idx_ops_record ON operations(collection, record_id);
CREATE INDEX IF NOT EXISTS idx_ops_node ON operations(node_id);

-- Current record state (materialized view of operations)
-- This is denormalized for fast reads
CREATE TABLE IF NOT EXISTS records (
    collection TEXT NOT NULL,
    record_id TEXT NOT NULL,
    version BIGINT NOT NULL,
    payload JSONB NOT NULL,
    deleted BOOLEAN DEFAULT FALSE,
    clock_counter BIGINT NOT NULL,
    clock_node_id TEXT NOT NULL,
    created_at BIGINT NOT NULL,
    updated_at BIGINT NOT NULL,
    PRIMARY KEY (collection, record_id)
);

-- Index for querying by collection
CREATE INDEX IF NOT EXISTS idx_records_collection ON records(collection);
CREATE INDEX IF NOT EXISTS idx_records_deleted ON records(deleted);

-- Registered client nodes
CREATE TABLE IF NOT EXISTS nodes (
    node_id TEXT PRIMARY KEY,
    last_sync_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
