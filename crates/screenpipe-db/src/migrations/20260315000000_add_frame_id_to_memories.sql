-- Add frame_id to memories for source provenance
ALTER TABLE memories ADD COLUMN frame_id INTEGER REFERENCES frames(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_memories_frame_id ON memories(frame_id);
