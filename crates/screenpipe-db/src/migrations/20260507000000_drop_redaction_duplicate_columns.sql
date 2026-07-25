-- The PII redaction worker is destructive-only now (commit aed06df83):
-- it overwrites the source column / source JPG instead of mirroring
-- the redacted output into a sibling column. That makes everything
-- the prior `20260501_*` and `20260503_*` migrations added except the
-- single "is processed" timestamp redundant. We drop the dead columns
-- here so the schema matches the worker's actual behavior — and so we
-- stop carrying ~2x duplicate text in the OCR/transcript tables.
--
-- What the worker keeps:
--   ocr_text.redacted_at,                       audio_transcriptions.redacted_at
--   frames.accessibility_redacted_at,           ui_events.redacted_at
--   frames.image_redacted_at
--
-- What we drop (dead after the destructive-only switch):
--   *.text_redacted               — the source column IS the redacted text now
--   *.redaction_version           — re-redaction not supported (raw text gone)
--   frames.accessibility_text_redacted, frames.accessibility_redaction_version
--   frames.image_redaction_version, frames.image_redaction_regions
--
-- SQLite has supported ALTER TABLE ... DROP COLUMN since 3.35 (Mar 2021).
-- Our libsqlite3-sys 0.26 ships SQLite 3.41+, so the bare DROP is safe
-- on every supported deployment.
--
-- Indexes on the dropped columns (none — all redaction indexes are on
-- *_redacted_at, which we keep) require no separate cleanup.

ALTER TABLE ocr_text             DROP COLUMN text_redacted;
ALTER TABLE ocr_text             DROP COLUMN redaction_version;

ALTER TABLE audio_transcriptions DROP COLUMN text_redacted;
ALTER TABLE audio_transcriptions DROP COLUMN redaction_version;

ALTER TABLE frames               DROP COLUMN accessibility_text_redacted;
ALTER TABLE frames               DROP COLUMN accessibility_redaction_version;

ALTER TABLE frames               DROP COLUMN image_redaction_version;
ALTER TABLE frames               DROP COLUMN image_redaction_regions;

ALTER TABLE ui_events            DROP COLUMN text_redacted;
ALTER TABLE ui_events            DROP COLUMN redaction_version;
