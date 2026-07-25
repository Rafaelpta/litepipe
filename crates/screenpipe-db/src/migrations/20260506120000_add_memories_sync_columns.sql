-- Cross-device memories sync. Mirrors the pattern used for pipe sync (the
-- payload travels through the same encrypted SyncManager via a new
-- BlobType::Memories), but each row in `memories` needs a stable identity
-- across machines so the merge can recognize the same memory on Device A
-- and Device B without colliding on local autoincrement ids.
--
-- sync_uuid       — null until the row is first synced; then a server-stable
--                    UUID that travels with the memory across machines.
-- sync_modified_by — machine id that last wrote this memory (LWW author tag).
ALTER TABLE memories ADD COLUMN sync_uuid TEXT;
ALTER TABLE memories ADD COLUMN sync_modified_by TEXT;

-- One row per uuid (NULL excluded) so we can SELECT … WHERE sync_uuid = ?
-- without a full scan, and so duplicate uuids are caught at INSERT time.
CREATE UNIQUE INDEX IF NOT EXISTS idx_memories_sync_uuid
    ON memories(sync_uuid) WHERE sync_uuid IS NOT NULL;
