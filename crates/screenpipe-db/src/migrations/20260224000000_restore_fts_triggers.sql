-- Restore synchronous AFTER INSERT triggers for FTS indexing.
--
-- The background FTS indexer (20260209000001) replaced these triggers to batch
-- writes, but created severe write lock contention on the single-writer SQLite
-- DB. FTS triggers add ~0.5-1ms per row — negligible — and eliminate the need
-- for the background indexer and its write semaphore.
--
-- frames_ai already exists (recreated by 20260220000000), so only 4 triggers
-- need to be restored: ocr_text, audio_transcriptions, accessibility, ui_events.
-- ui_monitoring is deprecated (replaced by ui_events) — no trigger restored.
--
-- NOTE: No backfill is done here. The triggers ensure all NEW data is indexed.
-- Data inserted during the Feb 10–24 gap (when triggers were absent) will have
-- incomplete FTS coverage, but this is acceptable — the alternative (bulk
-- INSERT...SELECT on a 3+ GB DB) would hold the write lock for minutes and
-- block all real-time captures.

-- 1. Restore AFTER INSERT trigger for ocr_text
CREATE TRIGGER IF NOT EXISTS ocr_text_ai AFTER INSERT ON ocr_text
WHEN NEW.text IS NOT NULL AND NEW.text != '' AND NEW.frame_id IS NOT NULL
BEGIN
    INSERT OR IGNORE INTO ocr_text_fts(frame_id, text, app_name, window_name)
    VALUES (
        NEW.frame_id,
        NEW.text,
        COALESCE(NEW.app_name, ''),
        COALESCE(NEW.window_name, '')
    );
END;

-- 2. Restore AFTER INSERT trigger for audio_transcriptions
CREATE TRIGGER IF NOT EXISTS audio_transcriptions_ai AFTER INSERT ON audio_transcriptions
WHEN NEW.transcription IS NOT NULL AND NEW.transcription != '' AND NEW.audio_chunk_id IS NOT NULL
BEGIN
    INSERT OR IGNORE INTO audio_transcriptions_fts(audio_chunk_id, transcription, device, speaker_id)
    VALUES (
        NEW.audio_chunk_id,
        NEW.transcription,
        COALESCE(NEW.device, ''),
        NEW.speaker_id
    );
END;

-- 3. Restore AFTER INSERT trigger for accessibility
CREATE TRIGGER IF NOT EXISTS accessibility_ai AFTER INSERT ON accessibility BEGIN
    INSERT OR IGNORE INTO accessibility_fts(rowid, text_content, app_name, window_name)
    VALUES (NEW.id, NEW.text_content, NEW.app_name, NEW.window_name);
END;

-- 4. Restore AFTER INSERT trigger for ui_events (was NEVER indexed by background indexer!)
CREATE TRIGGER IF NOT EXISTS ui_events_ai AFTER INSERT ON ui_events BEGIN
    INSERT OR IGNORE INTO ui_events_fts(rowid, text_content, app_name, window_title, element_name)
    VALUES (NEW.id, NEW.text_content, NEW.app_name, NEW.window_title, NEW.element_name);
END;

-- 5. Drop the background indexer progress table (no longer needed)
DROP TABLE IF EXISTS fts_index_progress;
