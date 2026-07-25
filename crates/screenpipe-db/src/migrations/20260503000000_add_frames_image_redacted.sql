-- Issue #3185 (image-PII follow-up): add per-frame redaction tracking
-- to the `frames` table so the new `screenpipe_redact::image::worker`
-- can reconcile screen-capture JPGs the same way the text worker
-- reconciles ocr_text / accessibility / audio_transcriptions / ui_events.
--
-- Schema convention mirrors `20260501000000_add_redacted_columns.sql`:
--
--   image_redacted_at       INTEGER  — unix-seconds the image redaction landed
--   image_redaction_version INTEGER  — model name+version that produced it
--   image_redaction_regions INTEGER  — # of regions that got blacked out (audit)
--
-- The "needs redaction" predicate is `image_redacted_at IS NULL OR
-- image_redaction_version < {current}`. Bumping the model's version
-- automatically queues every existing frame for re-redaction.
--
-- Naming note: prefixed with `image_` (vs. the bare `text_redacted` /
-- `redacted_at` columns the text tables grew) so a single frame row
-- can carry redaction state for both modalities without column-name
-- collisions if a future migration adds OCR-on-frame tracking here too.

ALTER TABLE frames ADD COLUMN image_redacted_at       INTEGER;
ALTER TABLE frames ADD COLUMN image_redaction_version INTEGER;
ALTER TABLE frames ADD COLUMN image_redaction_regions INTEGER;

-- Worker scans newest-first and filters by version + nullness; this
-- partial index is the cheap way to keep that scan fast as frames
-- accumulates millions of rows.
CREATE INDEX IF NOT EXISTS idx_frames_image_redaction_pending
    ON frames(id DESC)
    WHERE image_redacted_at IS NULL;
