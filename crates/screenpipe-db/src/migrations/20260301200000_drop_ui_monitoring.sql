-- Drop the deprecated ui_monitoring table and all associated objects.
-- Replaced by the `accessibility` table (text traversal) and `ui_events` table (input capture).

-- Drop triggers
DROP TRIGGER IF EXISTS ui_monitoring_ai;
DROP TRIGGER IF EXISTS ui_monitoring_update;
DROP TRIGGER IF EXISTS ui_monitoring_delete;

-- Drop FTS table + tags table + main table
DROP TABLE IF EXISTS ui_monitoring_fts;
DROP TABLE IF EXISTS ui_monitoring_tags;
DROP TABLE IF EXISTS ui_monitoring;
