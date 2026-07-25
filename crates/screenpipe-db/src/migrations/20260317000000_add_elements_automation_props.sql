-- Add automation properties to elements table for UI automation use cases.
-- Stored as a single JSON column to avoid sparse column bloat.
ALTER TABLE elements ADD COLUMN properties TEXT;
