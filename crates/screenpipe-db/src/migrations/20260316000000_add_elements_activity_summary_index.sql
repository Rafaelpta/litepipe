-- Covering index for the activity_summary query:
--   SELECT DISTINCT e.text, f.app_name, f.timestamp
--   FROM elements e JOIN frames f ON f.id = e.frame_id
--   WHERE ... e.text IS NOT NULL AND e.source IN (...) AND e.role IN (...)
--
-- The existing idx_elements_frame_source covers (frame_id, source) but the
-- query also filters on role and needs text. Without this index SQLite does
-- a full scan + sort on the elements table, taking 1-16 seconds on large DBs.
CREATE INDEX IF NOT EXISTS idx_elements_source_role_text
    ON elements(source, role, frame_id)
    WHERE text IS NOT NULL;
