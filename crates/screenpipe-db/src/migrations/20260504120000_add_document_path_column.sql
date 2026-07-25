-- Add absolute filesystem path of the document the focused window is editing,
-- when the platform exposes one (macOS reads from AXDocument). Browser URLs
-- continue to live in browser_url; this column is for editor file paths.
-- Stored as nullable since most frames (browsers, OS chrome, terminal-only
-- workflows, idle screens) won't have a document.
ALTER TABLE frames ADD COLUMN document_path TEXT DEFAULT NULL;
