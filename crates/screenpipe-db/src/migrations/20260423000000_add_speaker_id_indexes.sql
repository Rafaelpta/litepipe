-- Add missing speaker_id indexes that were causing 60s+ speaker similarity
-- queries (`get_similar_speakers`, plus the `RecentAudioPaths` CTE used by
-- speaker pickers and the diarization fallback path).
--
-- Diagnosed from a customer report (Ruark, ruark@ruark.xyz, v2.4.39): all
-- meeting transcripts were collapsing to a single "you" speaker because the
-- cosine-distance lookup was timing out and the diarization pipeline fell
-- back to the calendar-default user. Six consecutive sqlx WARNs each at
-- 60.6–60.9s elapsed on the same query in his log.
--
-- EXPLAIN QUERY PLAN on the offending query (see db.rs::get_similar_speakers
-- around line 5380) showed:
--   SCAN at                                                       ← full scan of audio_transcriptions
--   SEARCH se USING AUTOMATIC PARTIAL COVERING INDEX (speaker_id) ← rebuilt every query
--   SEARCH rap USING AUTOMATIC COVERING INDEX (speaker_id)        ← rebuilt every query
--   SCAN speaker_embeddings (×2 — one for WHERE, one for ORDER BY)
--
-- Three indexes fix it:
--
-- 1. `speaker_embeddings(speaker_id)` — eliminates the per-query
--    AUTOMATIC PARTIAL COVERING INDEX rebuild. This column is referenced
--    in WHERE / JOIN clauses across every diarization, similarity, and
--    centroid lookup path; not having an index here is pure overhead.
CREATE INDEX IF NOT EXISTS idx_speaker_embeddings_speaker_id
  ON speaker_embeddings(speaker_id);

-- 2. `audio_transcriptions(speaker_id, timestamp DESC)` — eliminates the
--    top-level SCAN of audio_transcriptions and makes the
--    "last 3 transcripts per speaker" subquery a pure index seek
--    (matches `WHERE at2.speaker_id = s.id ORDER BY timestamp DESC LIMIT 3`).
--    Composite + DESC because that's the exact access pattern.
CREATE INDEX IF NOT EXISTS idx_audio_transcriptions_speaker_id_timestamp
  ON audio_transcriptions(speaker_id, timestamp DESC);

-- Refresh planner stats so the new indexes are immediately preferred.
ANALYZE speaker_embeddings;
ANALYZE audio_transcriptions;
