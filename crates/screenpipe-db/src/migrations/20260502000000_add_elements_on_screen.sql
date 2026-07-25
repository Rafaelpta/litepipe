-- Add `on_screen` to elements: whether the element is visually present in
-- the captured screenshot at capture time. The accessibility tree captures
-- off-screen text (terminal scroll buffers, scrolled-off lines in IDE
-- editors) which then matched against full-text search even when the
-- user couldn't see it — see issue #2436.
--
-- Stored as nullable INTEGER (SQLite boolean): 1 = on-screen, 0 = off-screen,
-- NULL = unknown. NULL is the default for old rows captured before the
-- a11y walker started reporting this signal — no backfill is possible
-- because we don't have the historical window rect.
--
-- Filter semantics in /search and /elements: when on_screen=true is
-- passed, NULL rows are excluded (strict on-screen). Without the filter,
-- behavior is unchanged so existing pipes / queries keep returning
-- everything they used to.
ALTER TABLE elements ADD COLUMN on_screen INTEGER;

-- Partial index for the common "show only on-screen elements" filter.
-- WHERE-clause keeps the index small (NULL rows aren't indexed) so it
-- only costs storage proportional to the post-fix data, not the legacy
-- backlog.
CREATE INDEX IF NOT EXISTS idx_elements_on_screen
    ON elements(frame_id, on_screen)
    WHERE on_screen IS NOT NULL;
