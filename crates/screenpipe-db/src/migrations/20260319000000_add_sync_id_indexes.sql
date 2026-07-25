-- Add missing sync_id indexes to prevent full table scans during sync existence checks.
-- These queries run on every sync cycle and were causing 1-5s full scans on 300K+ row tables,
-- cascading into WAL checkpoint delays and 140s+ vision write stalls.

CREATE INDEX IF NOT EXISTS idx_frames_sync_id ON frames(sync_id) WHERE sync_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_ocr_text_sync_id ON ocr_text(sync_id) WHERE sync_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_audio_transcriptions_sync_id ON audio_transcriptions(sync_id) WHERE sync_id IS NOT NULL;

-- Also add index for elements join query that scans 4M+ rows.
-- The query filters frames by timestamp then joins elements — this index lets
-- SQLite start from frame_id (small result set) instead of source+role (millions).
CREATE INDEX IF NOT EXISTS idx_elements_frame_source_role ON elements(frame_id, source, role) WHERE text IS NOT NULL;
