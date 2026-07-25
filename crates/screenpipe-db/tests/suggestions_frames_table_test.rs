#[cfg(test)]
mod tests {
    use chrono::Utc;
    use screenpipe_db::DatabaseManager;

    async fn setup_test_db() -> DatabaseManager {
        let db = DatabaseManager::new("sqlite::memory:", Default::default())
            .await
            .unwrap();
        sqlx::migrate!("./src/migrations")
            .run(&db.pool)
            .await
            .unwrap();
        db
    }

    /// Test that frames.full_text column exists and can be queried
    /// (verification for fix: suggestions.rs using frames instead of accessibility table)
    #[tokio::test]
    async fn test_frames_full_text_column_exists() {
        let db = setup_test_db().await;

        // Insert a frame with accessibility text
        let _frame_id = db
            .insert_snapshot_frame(
                "test_device",
                Utc::now(),
                "/tmp/test.jpg",
                Some("Chrome"),
                Some("Test Window"),
                None,
                true,
                Some("event"),
                Some("Sample accessibility text content"),
                Some("accessibility"),
                None,
                None,
                None,
            )
            .await
            .unwrap();

        // Query the frames table for full_text column with the exact query from suggestions.rs
        let result: Result<Vec<(String, String, String)>, _> = sqlx::query_as(
            "SELECT app_name, window_name, SUBSTR(full_text, 1, 200) as snippet FROM frames WHERE datetime(timestamp) > datetime('now', '-15 minutes') AND LENGTH(full_text) > 30 AND app_name != 'screenpipe' AND full_text IS NOT NULL ORDER BY timestamp DESC LIMIT 8"
        )
        .fetch_all(&db.pool)
        .await;

        assert!(result.is_ok(), "Query should succeed");
        let rows = result.unwrap();
        assert!(
            !rows.is_empty(),
            "Should find at least one frame with full_text"
        );
        assert_eq!(rows[0].0, "Chrome");
        assert_eq!(rows[0].1, "Test Window");
        assert!(rows[0].2.contains("Sample accessibility text"));
    }

    /// Test that count_accessibility_rows query works on frames table
    #[tokio::test]
    async fn test_count_accessibility_rows_on_frames_table() {
        let db = setup_test_db().await;

        // Insert a frame
        let _frame_id = db
            .insert_snapshot_frame(
                "test_device",
                Utc::now(),
                "/tmp/test.jpg",
                Some("Safari"),
                Some("Test Page"),
                None,
                true,
                Some("event"),
                Some("Some accessibility content here"),
                Some("accessibility"),
                None,
                None,
                None,
            )
            .await
            .unwrap();

        // Query the count using the exact query from suggestions.rs
        let result: Result<Vec<(i64,)>, _> = sqlx::query_as(
            "SELECT COUNT(*) as cnt FROM frames WHERE datetime(timestamp) > datetime('now', '-30 minutes') AND full_text IS NOT NULL"
        )
        .fetch_all(&db.pool)
        .await;

        assert!(result.is_ok(), "Count query should succeed");
        let rows = result.unwrap();
        assert!(!rows.is_empty(), "Should have at least one result row");
        assert_eq!(
            rows[0].0, 1,
            "Should count exactly one frame with full_text"
        );
    }

    /// Verify that the 'accessibility' table doesn't exist anymore
    /// (ensures we're not accidentally using a dropped table)
    #[tokio::test]
    async fn test_accessibility_table_dropped() {
        let db = setup_test_db().await;

        // Try to query the old accessibility table - should fail
        let result: Result<Vec<(i64,)>, _> =
            sqlx::query_as("SELECT COUNT(*) as cnt FROM accessibility")
                .fetch_all(&db.pool)
                .await;

        assert!(
            result.is_err(),
            "accessibility table should not exist; fix uses frames.full_text instead"
        );
    }
}
