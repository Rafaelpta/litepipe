-- Media-only retention: track when a chunk's mp4/wav was evicted from disk
-- while keeping its DB row (frames, ocr_text, transcriptions) intact for
-- search and timeline. NULL means the file is still on disk.
--
-- file_path stays NOT NULL — eviction sets it to '' (empty string) so
-- loaders can early-out without dereferencing a stale path.

ALTER TABLE video_chunks ADD COLUMN evicted_at TIMESTAMP DEFAULT NULL;
ALTER TABLE audio_chunks ADD COLUMN evicted_at TIMESTAMP DEFAULT NULL;
