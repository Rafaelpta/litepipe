-- Elements table: unified structured storage for OCR + accessibility screen content
CREATE TABLE IF NOT EXISTS elements (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    frame_id INTEGER NOT NULL,
    source TEXT NOT NULL,             -- 'ocr' | 'accessibility'
    role TEXT NOT NULL,               -- OCR: 'page','block','paragraph','line','word'
                                      -- AX: 'AXButton','AXTextField','AXStaticText', etc.
    text TEXT,                        -- element text content (NULL for container nodes)
    parent_id INTEGER,               -- self-referential FK for tree hierarchy (NULL = root)
    depth INTEGER NOT NULL DEFAULT 0, -- tree depth (0 = root)
    left_bound REAL,                 -- normalized 0-1 bounding box
    top_bound REAL,
    width_bound REAL,
    height_bound REAL,
    confidence REAL,                 -- OCR confidence (0-100), NULL for AX
    sort_order INTEGER NOT NULL DEFAULT 0, -- sibling order within parent
    FOREIGN KEY (frame_id) REFERENCES frames(id),
    FOREIGN KEY (parent_id) REFERENCES elements(id)
);

CREATE INDEX IF NOT EXISTS idx_elements_frame_id ON elements(frame_id);
CREATE INDEX IF NOT EXISTS idx_elements_parent_id ON elements(parent_id);
CREATE INDEX IF NOT EXISTS idx_elements_source ON elements(source);
CREATE INDEX IF NOT EXISTS idx_elements_frame_source ON elements(frame_id, source);

-- FTS5 with content-sync: reads come from the elements table, no data duplication
CREATE VIRTUAL TABLE IF NOT EXISTS elements_fts USING fts5(
    text,
    role,
    frame_id UNINDEXED,
    content='elements',
    content_rowid='id',
    tokenize='unicode61'
);

-- Synchronous trigger: index text elements on insert
CREATE TRIGGER IF NOT EXISTS elements_ai AFTER INSERT ON elements
WHEN NEW.text IS NOT NULL AND NEW.text != ''
BEGIN
    INSERT INTO elements_fts(rowid, text, role, frame_id)
    VALUES (NEW.id, NEW.text, NEW.role, NEW.frame_id);
END;

-- Delete trigger
CREATE TRIGGER IF NOT EXISTS elements_ad AFTER DELETE ON elements
WHEN OLD.text IS NOT NULL AND OLD.text != ''
BEGIN
    INSERT INTO elements_fts(elements_fts, rowid, text, role, frame_id)
    VALUES ('delete', OLD.id, OLD.text, OLD.role, OLD.frame_id);
END;

-- Update trigger
CREATE TRIGGER IF NOT EXISTS elements_au AFTER UPDATE ON elements
WHEN OLD.text IS NOT NULL AND OLD.text != ''
BEGIN
    INSERT INTO elements_fts(elements_fts, rowid, text, role, frame_id)
    VALUES ('delete', OLD.id, OLD.text, OLD.role, OLD.frame_id);
    INSERT INTO elements_fts(rowid, text, role, frame_id)
    VALUES (NEW.id, NEW.text, NEW.role, NEW.frame_id);
END;
