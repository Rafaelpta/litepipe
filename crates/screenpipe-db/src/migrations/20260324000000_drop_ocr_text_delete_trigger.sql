-- The 20260312000001 migration dropped ocr_text_fts but used wrong trigger
-- names (_ad, _au) instead of the actual names (_delete, _update) created
-- by 20260301100000. These orphaned triggers fire on DELETE/UPDATE of
-- ocr_text and error with "no such table: main.ocr_text_fts".
DROP TRIGGER IF EXISTS ocr_text_delete;
DROP TRIGGER IF EXISTS ocr_text_update;
