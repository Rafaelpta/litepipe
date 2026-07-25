CREATE TABLE IF NOT EXISTS meetings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    meeting_start TEXT NOT NULL,
    meeting_end TEXT,
    meeting_app TEXT NOT NULL,
    title TEXT,
    attendees TEXT,
    detection_source TEXT NOT NULL DEFAULT 'app',
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_meetings_start ON meetings(meeting_start);
CREATE INDEX IF NOT EXISTS idx_meetings_end ON meetings(meeting_end);
