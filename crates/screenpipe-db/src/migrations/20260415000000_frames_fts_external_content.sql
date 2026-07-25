-- Convert frames_fts to content='frames' external content mode.
--
-- Background:
-- 20260301100000 already converted ocr_text_fts and audio_transcriptions_fts
-- to external content. frames_fts was recreated 11 days later in
-- 20260312000000 but kept the standalone layout, so it still stores a full
-- duplicate copy of every frame's full_text/app_name/window_name/browser_url
-- and its DELETE trigger rewrites the inverted index per row.
--
-- Before 20260321 the per-row rewrite was fine because DELETE was rare
-- (manual only). The 14-day retention loop added in b70a09665 turned that
-- assumption false — retention batches now DELETE thousands of frames every
-- tick, and the frames_ad trigger dominates the wall-clock cost:
--   - DELETE 951 frames with trigger on:  ~38 s
--   - DELETE 951 frames with trigger off: ~0.09 s (~420x)
--
-- Switching to content='frames' stores no duplicate text (saves ~175 MB on
-- a 14-day DB), and lets triggers do logical deletes via the 'delete'
-- command, which doesn't rewrite postings on a per-row basis.
--
-- Interruption behavior:
-- All DDL uses IF EXISTS / IF NOT EXISTS guards and sqlx wraps the migration
-- in a transaction, so a killed migration rolls back cleanly and the next
-- run replays from a consistent starting state. The only slow step is the
-- rebuild INSERT; on very large DBs (500k+ frames) it can take minutes, but
-- it is atomic — either it commits and sqlx marks the migration complete,
-- or it rolls back and replays next launch. Same characteristic as the
-- 20260301100000 migration.

PRAGMA foreign_keys = OFF;

-- 1. Drop old standalone-mode triggers and the table itself.
DROP TRIGGER IF EXISTS frames_ai;
DROP TRIGGER IF EXISTS frames_au;
DROP TRIGGER IF EXISTS frames_ad;
DROP TABLE IF EXISTS frames_fts;

-- 2. Recreate as external content. rowid maps to frames.id via
-- content_rowid, so queries that previously used frames_fts.id should
-- use frames_fts.rowid instead.
CREATE VIRTUAL TABLE frames_fts USING fts5(
    full_text,
    app_name,
    window_name,
    browser_url,
    content='frames',
    content_rowid='id',
    tokenize='unicode61'
);

-- 3. Backfill the inverted index from frames rows that should actually be
-- searchable. This preserves the trigger semantics below: metadata-only rows
-- without OCR text are not indexed.
INSERT INTO frames_fts(rowid, full_text, app_name, window_name, browser_url)
SELECT
    id,
    full_text,
    COALESCE(app_name, ''),
    COALESCE(window_name, ''),
    COALESCE(browser_url, '')
FROM frames
WHERE full_text IS NOT NULL AND full_text != '';

-- 4. Recreate triggers for external content mode.
-- External content requires explicit INSERT/DELETE on the FTS table to
-- keep the index in sync. UPDATE = logical delete (OLD) + insert (NEW).
-- The 'delete' command needs OLD's indexed values so FTS5 can subtract
-- the right postings from the inverted index.

CREATE TRIGGER frames_ai AFTER INSERT ON frames
WHEN NEW.full_text IS NOT NULL AND NEW.full_text != ''
BEGIN
    INSERT INTO frames_fts(rowid, full_text, app_name, window_name, browser_url)
    VALUES (
        NEW.id,
        NEW.full_text,
        COALESCE(NEW.app_name, ''),
        COALESCE(NEW.window_name, ''),
        COALESCE(NEW.browser_url, '')
    );
END;

CREATE TRIGGER frames_ad AFTER DELETE ON frames
WHEN OLD.full_text IS NOT NULL AND OLD.full_text != ''
BEGIN
    INSERT INTO frames_fts(frames_fts, rowid, full_text, app_name, window_name, browser_url)
    VALUES (
        'delete',
        OLD.id,
        OLD.full_text,
        COALESCE(OLD.app_name, ''),
        COALESCE(OLD.window_name, ''),
        COALESCE(OLD.browser_url, '')
    );
END;

CREATE TRIGGER frames_au AFTER UPDATE OF full_text, app_name, window_name, browser_url ON frames
BEGIN
    -- remove old tokens if the old row was indexed
    INSERT INTO frames_fts(frames_fts, rowid, full_text, app_name, window_name, browser_url)
    SELECT
        'delete',
        OLD.id,
        OLD.full_text,
        COALESCE(OLD.app_name, ''),
        COALESCE(OLD.window_name, ''),
        COALESCE(OLD.browser_url, '')
    WHERE OLD.full_text IS NOT NULL AND OLD.full_text != '';

    -- insert new tokens if the new row should be indexed
    INSERT INTO frames_fts(rowid, full_text, app_name, window_name, browser_url)
    SELECT
        NEW.id,
        NEW.full_text,
        COALESCE(NEW.app_name, ''),
        COALESCE(NEW.window_name, ''),
        COALESCE(NEW.browser_url, '')
    WHERE NEW.full_text IS NOT NULL AND NEW.full_text != '';
END;

PRAGMA foreign_keys = ON;
