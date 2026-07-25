-- Add elements_ref_frame_id to frames table for element deduplication.
-- When consecutive frames from the same device have identical content_hash,
-- the new frame references the previous frame's elements instead of inserting duplicates.
ALTER TABLE frames ADD COLUMN elements_ref_frame_id INTEGER DEFAULT NULL;
