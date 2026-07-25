//! End-to-end: spin up an in-memory SQLite, seed all five target
//! tables (ocr, audio, accessibility, ui_events:keyboard,
//! ui_events:clipboard), run the worker for a few cycles, assert
//! every source column gets overwritten with the redacted text and
//! the corresponding `*_redacted_at` timestamp is stamped.

use std::sync::Arc;
use std::time::Duration;

use screenpipe_redact::{
    adapters::regex::RegexRedactor,
    worker::{TargetTable, Worker, WorkerConfig, ALL_TARGET_TABLES},
    Redactor,
};
use sqlx::sqlite::SqlitePoolOptions;
use sqlx::Row;

async fn setup_db() -> sqlx::SqlitePool {
    let pool = SqlitePoolOptions::new()
        .max_connections(2)
        .connect("sqlite::memory:")
        .await
        .unwrap();

    // Mirror the production schema after the 20260507 drop-duplicates
    // migration: each text-bearing table keeps just the source column
    // + a single `*_redacted_at` "is processed" timestamp. The worker
    // overwrites the source in place; no sibling text_redacted column.
    sqlx::query(
        r#"
        CREATE TABLE ocr_text (
            frame_id INTEGER PRIMARY KEY,
            text TEXT NOT NULL,
            redacted_at INTEGER
        );
        CREATE TABLE audio_transcriptions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            transcription TEXT NOT NULL,
            redacted_at INTEGER
        );
        -- Accessibility text moved to `frames.accessibility_text` after
        -- the 2026-03-12 consolidation; only the prefixed timestamp
        -- survives the destructive-only refactor.
        CREATE TABLE frames (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            accessibility_text TEXT,
            accessibility_redacted_at INTEGER
        );
        CREATE TABLE ui_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            event_type TEXT NOT NULL,
            text_content TEXT,
            redacted_at INTEGER
        );
        "#,
    )
    .execute(&pool)
    .await
    .unwrap();

    pool
}

/// Seed each target with a row containing PII the regex catches.
async fn seed(pool: &sqlx::SqlitePool) {
    sqlx::query(
        "INSERT INTO ocr_text (frame_id, text) VALUES (1, 'Hi alice@example.com — meeting at 3pm')",
    )
    .execute(pool)
    .await
    .unwrap();
    sqlx::query("INSERT INTO audio_transcriptions (transcription) VALUES ('the api key is sk-proj-AbCdEf123456GhIjKlMnOp tomorrow')")
        .execute(pool).await.unwrap();
    sqlx::query(
        "INSERT INTO frames (accessibility_text) VALUES ('AXButton[Send to bob@example.com]')",
    )
    .execute(pool)
    .await
    .unwrap();
    // ui_events: one keyboard event + one clipboard event.
    sqlx::query(
        "INSERT INTO ui_events (event_type, text_content) VALUES ('text', 'typed: AKIAIOSFODNN7EXAMPLE')",
    )
    .execute(pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO ui_events (event_type, text_content) VALUES ('clipboard', 'pasted bob@example.com to the form')",
    )
    .execute(pool)
    .await
    .unwrap();
}

#[tokio::test]
async fn worker_redacts_all_five_targets() {
    let pool = setup_db().await;
    seed(&pool).await;

    let redactor = Arc::new(RegexRedactor::new()) as Arc<dyn Redactor>;
    let cfg = WorkerConfig {
        batch_size: 16,
        idle_between_batches: Duration::from_millis(1),
        poll_interval: Duration::from_millis(20),
        tables: ALL_TARGET_TABLES.to_vec(),
    };
    let worker = Worker::new(pool.clone(), redactor, cfg);
    let handle = worker.clone().spawn();

    // Give the worker a moment to drain the queue.
    tokio::time::sleep(Duration::from_millis(200)).await;
    handle.abort();

    // Every seeded row should now have its source column overwritten
    // with the redacted version + redacted_at stamped.
    for target in [
        TargetTable::Ocr,
        TargetTable::AudioTranscription,
        TargetTable::Accessibility,
        TargetTable::UiEventsKeyboard,
        TargetTable::UiEventsClipboard,
    ] {
        let extra = target
            .extra_filter()
            .map(|f| format!(" AND {}", f))
            .unwrap_or_default();
        let q = format!(
            "SELECT {src} AS r, {redacted_at} AS w FROM {tbl} \
             WHERE {redacted_at} IS NOT NULL{extra}",
            src = target.source_col(),
            redacted_at = target.redacted_at_col(),
            tbl = target.table(),
            extra = extra
        );
        let rows = sqlx::query(&q).fetch_all(&pool).await.unwrap();
        assert!(
            !rows.is_empty(),
            "expected ≥1 redacted row in {} after worker drained",
            target.label()
        );
        let red: String = rows[0].get(0);
        let when: i64 = rows[0].get(1);
        assert!(
            when > 0,
            "{}: redacted_at should be stamped",
            target.label()
        );
        assert!(
            red.contains("[EMAIL]") || red.contains("[SECRET]"),
            "{}: source column {:?} doesn't contain a placeholder — destructive overwrite did not happen",
            target.label(),
            red
        );
    }

    let status = worker.status().await;
    assert!(status.running);
    assert_eq!(status.redacted_total, 5);
    assert!(status.last_redacted_at.is_some());
}

#[tokio::test]
async fn worker_skips_already_redacted_rows() {
    let pool = setup_db().await;
    // Frame 1 is already processed — source already redacted, redacted_at set.
    sqlx::query("INSERT INTO ocr_text (frame_id, text, redacted_at) VALUES (1, '[EMAIL]', 1)")
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("INSERT INTO ocr_text (frame_id, text) VALUES (2, 'bob@example.com')")
        .execute(&pool)
        .await
        .unwrap();

    let redactor = Arc::new(RegexRedactor::new()) as Arc<dyn Redactor>;
    let cfg = WorkerConfig {
        idle_between_batches: Duration::from_millis(1),
        poll_interval: Duration::from_millis(20),
        ..Default::default()
    };
    let worker = Worker::new(pool.clone(), redactor, cfg);
    let handle = worker.clone().spawn();

    tokio::time::sleep(Duration::from_millis(120)).await;
    handle.abort();

    let status = worker.status().await;
    // Only the un-redacted frame should have been processed.
    assert_eq!(status.redacted_total, 1);
}

#[tokio::test]
async fn worker_overwrites_source_columns_destructively() {
    let pool = setup_db().await;
    sqlx::query(
        "INSERT INTO ocr_text (frame_id, text) VALUES (1, 'alice@example.com is the email')",
    )
    .execute(&pool)
    .await
    .unwrap();

    let redactor = Arc::new(RegexRedactor::new()) as Arc<dyn Redactor>;
    let cfg = WorkerConfig {
        idle_between_batches: Duration::from_millis(1),
        poll_interval: Duration::from_millis(20),
        tables: vec![TargetTable::Ocr],
        ..Default::default()
    };
    let worker = Worker::new(pool.clone(), redactor, cfg);
    let handle = worker.clone().spawn();

    tokio::time::sleep(Duration::from_millis(120)).await;
    handle.abort();

    let row = sqlx::query("SELECT text, redacted_at FROM ocr_text WHERE frame_id = 1")
        .fetch_one(&pool)
        .await
        .unwrap();
    let raw: String = row.get(0);
    let when: Option<i64> = row.get(1);
    // Source column overwritten — raw email gone forever.
    assert!(
        !raw.contains("alice@example.com"),
        "left raw email in source column: {:?}",
        raw
    );
    assert!(raw.contains("[EMAIL]"));
    assert!(when.is_some(), "redacted_at must be stamped");
}
