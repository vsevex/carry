//! Performance benchmarks for carry-engine

use carry_engine::{
    CollectionSchema, CreateOp, FieldDef, FieldType, LogicalClock, MergeStrategy, Operation,
    Schema, Store,
};
use criterion::{black_box, criterion_group, criterion_main, BenchmarkId, Criterion};
use serde_json::json;

fn create_test_schema() -> Schema {
    let mut schema = Schema::new(1);
    let fields = vec![
        FieldDef::required("name", FieldType::String),
        FieldDef::optional("email", FieldType::String),
        FieldDef::optional("age", FieldType::Int),
    ];
    let collection = CollectionSchema::new("users", fields);
    schema.add_collection(collection);
    schema
}

fn bench_store_operations(c: &mut Criterion) {
    let mut group = c.benchmark_group("store_operations");

    // Benchmark store creation
    group.bench_function("store_new", |b| {
        b.iter(|| {
            let schema = create_test_schema();
            Store::new(black_box(schema), black_box("node1".to_string()))
        })
    });

    // Benchmark apply create
    group.bench_function("apply_create", |b| {
        let schema = create_test_schema();
        let mut store = Store::new(schema, "node1".to_string());
        let mut id = 0u64;

        b.iter(|| {
            id += 1;
            let op = Operation::Create(CreateOp::new(
                format!("op_{}", id),
                format!("user_{}", id),
                "users",
                json!({"name": "Test User"}),
                1000,
                LogicalClock::with_counter("node1", id),
            ));
            store.apply(black_box(op), black_box(1000))
        })
    });

    // Benchmark get operation
    group.bench_function("get_record", |b| {
        let schema = create_test_schema();
        let mut store = Store::new(schema, "node1".to_string());

        // Pre-populate with 1000 records
        for i in 0..1000u64 {
            let op = Operation::Create(CreateOp::new(
                format!("op_{}", i),
                format!("user_{}", i),
                "users",
                json!({"name": format!("User {}", i)}),
                1000,
                LogicalClock::with_counter("node1", i),
            ));
            let _ = store.apply(op, 1000);
        }

        b.iter(|| store.get(black_box("users"), black_box("user_500")))
    });

    // Benchmark query operation
    group.bench_function("query_all", |b| {
        let schema = create_test_schema();
        let mut store = Store::new(schema, "node1".to_string());

        // Pre-populate with 1000 records
        for i in 0..1000u64 {
            let op = Operation::Create(CreateOp::new(
                format!("op_{}", i),
                format!("user_{}", i),
                "users",
                json!({"name": format!("User {}", i)}),
                1000,
                LogicalClock::with_counter("node1", i),
            ));
            let _ = store.apply(op, 1000);
        }

        b.iter(|| store.query(black_box("users")).unwrap().all())
    });

    group.finish();
}

fn bench_reconciliation(c: &mut Criterion) {
    let mut group = c.benchmark_group("reconciliation");

    for size in [10, 100, 500].iter() {
        group.bench_with_input(BenchmarkId::new("reconcile_ops", size), size, |b, &size| {
            b.iter(|| {
                let schema = create_test_schema();
                let mut store = Store::new(schema, "local".to_string());

                // Create local operations
                for i in 0..(size / 2) {
                    let op = Operation::Create(CreateOp::new(
                        format!("local_op_{}", i),
                        format!("user_{}", i),
                        "users",
                        json!({"name": format!("Local User {}", i)}),
                        1000 + i as u64,
                        LogicalClock::with_counter("local", i as u64),
                    ));
                    let _ = store.apply(op, 1000 + i as u64);
                }

                // Create remote operations (some overlapping)
                let remote_ops: Vec<Operation> = (0..(size / 2))
                    .map(|i| {
                        Operation::Create(CreateOp::new(
                            format!("remote_op_{}", i),
                            format!("user_{}", i + size / 4), // Some overlap
                            "users",
                            json!({"name": format!("Remote User {}", i)}),
                            2000 + i as u64,
                            LogicalClock::with_counter("remote", i as u64 + 100),
                        ))
                    })
                    .collect();

                store.reconcile(black_box(remote_ops), black_box(MergeStrategy::ClockWins))
            })
        });
    }

    group.finish();
}

fn bench_snapshot(c: &mut Criterion) {
    let mut group = c.benchmark_group("snapshot");

    for size in [100, 500, 1000].iter() {
        group.bench_with_input(BenchmarkId::new("export", size), size, |b, &size| {
            let schema = create_test_schema();
            let mut store = Store::new(schema, "node1".to_string());

            // Pre-populate
            for i in 0..size {
                let op = Operation::Create(CreateOp::new(
                    format!("op_{}", i),
                    format!("user_{}", i),
                    "users",
                    json!({"name": format!("User {}", i), "email": format!("user{}@test.com", i)}),
                    1000,
                    LogicalClock::with_counter("node1", i as u64),
                ));
                let _ = store.apply(op, 1000);
            }

            b.iter(|| store.export_state())
        });

        group.bench_with_input(BenchmarkId::new("import", size), size, |b, &size| {
            let schema = create_test_schema();
            let mut store = Store::new(schema.clone(), "node1".to_string());

            // Pre-populate and export
            for i in 0..size {
                let op = Operation::Create(CreateOp::new(
                    format!("op_{}", i),
                    format!("user_{}", i),
                    "users",
                    json!({"name": format!("User {}", i)}),
                    1000,
                    LogicalClock::with_counter("node1", i as u64),
                ));
                let _ = store.apply(op, 1000);
            }
            let snapshot = store.export_state();

            b.iter(|| {
                let mut new_store = Store::new(schema.clone(), "node1".to_string());
                new_store.import_state(black_box(snapshot.clone()))
            })
        });
    }

    group.finish();
}

fn bench_serialization(c: &mut Criterion) {
    let mut group = c.benchmark_group("serialization");

    // Operation serialization
    group.bench_function("operation_to_json", |b| {
        let op = Operation::Create(CreateOp::new(
            "op_1",
            "user_1",
            "users",
            json!({"name": "Test User", "email": "test@example.com", "age": 30}),
            1000,
            LogicalClock::with_counter("node1", 1),
        ));

        b.iter(|| serde_json::to_string(black_box(&op)))
    });

    group.bench_function("operation_from_json", |b| {
        let json = r#"{"Create":{"opId":"op_1","id":"user_1","collection":"users","payload":{"name":"Test User"},"timestamp":1000,"clock":{"counter":1,"nodeId":"node1"}}}"#;

        b.iter(|| serde_json::from_str::<Operation>(black_box(json)))
    });

    group.finish();
}

criterion_group!(
    benches,
    bench_store_operations,
    bench_reconciliation,
    bench_snapshot,
    bench_serialization,
);
criterion_main!(benches);
