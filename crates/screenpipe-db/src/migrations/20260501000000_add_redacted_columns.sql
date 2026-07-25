-- Issue #3185: optional confidential-compute PII redaction (background reconciliation)
--
-- Add `text_redacted` / `redacted_at` / `redaction_version` columns to
-- the text-bearing tables. Additive, non-breaking; old rows have NULL
-- on all three until the reconciliation worker catches up.
--
-- Schema convention:
--   text_redacted     TEXT     — redacted version of the source column
--   redacted_at       INTEGER  — unix-seconds the redaction landed
--   redaction_version INTEGER  — name+version of the redactor that produced it
--
-- The "needs redaction" predicate is `text_redacted IS NULL OR
-- redaction_version < {current}`. That makes re-redaction free when
-- the worker's redactor version bumps.
--
-- Note on the accessibility surface: an earlier draft of this migration
-- targeted the standalone `accessibility` table. That table was
-- consolidated into `frames.accessibility_text` (and `frames.full_text`)
-- by `20260312000001_drop_dead_fts_tables.sql`, and the standalone table
-- no longer exists on any current database. Accessibility-text
-- redaction now writes to `frames.accessibility_text_redacted`, added
-- here alongside the OCR / transcript / ui_events columns so the worker
-- has a single migration to gate on.

-- OCR text from screen captures.
ALTER TABLE ocr_text ADD COLUMN text_redacted     TEXT;
ALTER TABLE ocr_text ADD COLUMN redacted_at       INTEGER;
ALTER TABLE ocr_text ADD COLUMN redaction_version INTEGER;

-- Audio transcripts.
ALTER TABLE audio_transcriptions ADD COLUMN text_redacted     TEXT;
ALTER TABLE audio_transcriptions ADD COLUMN redacted_at       INTEGER;
ALTER TABLE audio_transcriptions ADD COLUMN redaction_version INTEGER;

-- Accessibility-tree text — now lives at `frames.accessibility_text`.
-- We add a sibling redacted column rather than overloading the
-- `frames.full_text` consolidated field, so OCR text and accessibility
-- text retain independent redaction state (a future improvement could
-- recompute full_text from the redacted parts on read).
ALTER TABLE frames ADD COLUMN accessibility_text_redacted TEXT;
ALTER TABLE frames ADD COLUMN accessibility_redacted_at   INTEGER;
ALTER TABLE frames ADD COLUMN accessibility_redaction_version INTEGER;

-- UI events: typed keystrokes, clicks, clipboard payloads.
-- The reconciliation worker only touches rows where `event_type IN
-- ('text','key','clipboard')`; the redaction columns exist on every
-- row but stay NULL for rows we don't process (clicks, focus events).
ALTER TABLE ui_events ADD COLUMN text_redacted     TEXT;
ALTER TABLE ui_events ADD COLUMN redacted_at       INTEGER;
ALTER TABLE ui_events ADD COLUMN redaction_version INTEGER;

-- Indexes on `redacted_at` so the worker's "needs redaction" query
-- (which scans by primary key DESC) is cheap, and so search-time
-- "show me only redacted rows" filters are cheap too.
CREATE INDEX IF NOT EXISTS idx_ocr_text_redacted_at             ON ocr_text(redacted_at);
CREATE INDEX IF NOT EXISTS idx_audio_transcriptions_redacted_at ON audio_transcriptions(redacted_at);
CREATE INDEX IF NOT EXISTS idx_frames_accessibility_redacted_at ON frames(accessibility_redacted_at);
CREATE INDEX IF NOT EXISTS idx_ui_events_redacted_at            ON ui_events(redacted_at);

-- For the ui_events scan we also benefit from a (event_type,
-- redacted_at) compound — keyboard-only / clipboard-only fetches
-- otherwise scan the whole table.
CREATE INDEX IF NOT EXISTS idx_ui_events_type_redacted_at
  ON ui_events(event_type, redacted_at);
