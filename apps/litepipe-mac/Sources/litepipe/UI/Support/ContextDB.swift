import Foundation
import SQLite3

/// Read-only reader over the live litepipe archive. Opens with SQLITE_OPEN_READONLY
/// and never writes, so it is safe to run while the engine is capturing.
enum ContextDB {
    /// Opens the archive for reading, and copes with the one case where asking
    /// for read only makes reading impossible.
    ///
    /// The engine writes in WAL mode. A WAL database needs a shared memory file
    /// beside it, and SQLite deletes that file when the last connection closes
    /// cleanly. A read only connection is not allowed to recreate it, so opening
    /// the archive fails with "unable to open database file" precisely when
    /// nothing else has it open: engine stopped, app closed, which is the state
    /// an agent asks a question in.
    ///
    /// So: read only first, which is right whenever capture is running, and on
    /// failure open normally so SQLite may lay the file back down. Nothing here
    /// writes a row either way; only SELECT is ever prepared.
    static func open(_ path: String = defaultPath) -> OpaquePointer? {
        var db: OpaquePointer?
        let readOnly = "file:\(path)?mode=ro&immutable=0"
        if sqlite3_open_v2(readOnly, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK,
           let db, sqlite3_exec(db, "SELECT 1 FROM sqlite_master LIMIT 1;", nil, nil, nil) == SQLITE_OK {
            sqlite3_busy_timeout(db, 3000)
            return db
        }
        sqlite3_close(db)
        db = nil
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let opened = db else {
            sqlite3_close(db)
            return nil
        }
        sqlite3_busy_timeout(opened, 3000)
        return opened
    }

    /// LITEPIPE_DB points the reader at a different archive. The window never
    /// writes, so this costs nothing to ship, and it is the only way to see what
    /// a fresh install looks like from a Mac that has been capturing for weeks:
    /// an empty archive cannot be faked on a full one.
    static let defaultPath = ProcessInfo.processInfo.environment["LITEPIPE_DB"]
        ?? NSHomeDirectory() + "/.litepipe/db.sqlite"

    struct TranscriptLine: Identifiable, Hashable {
        let id: Int64
        let at: Date
        let speaker: String
        let isMe: Bool
        let text: String
    }

    struct Meeting: Identifiable, Hashable {
        let id: Int64
        let start: Date
        let end: Date?
        let app: String
        let title: String?

        func contains(_ t: Date) -> Bool { t >= start && t <= (end ?? .distantFuture) }
    }

    struct Load {
        var items: [Photo] = []
        var meetings: [Meeting] = []
        var transcripts: [Int64: [TranscriptLine]] = [:]
        var uiEventCount = 0
        var elementCount = 0
        var error: String?
        /// The oldest capture this page reached, which is where the next page
        /// starts. Nil when the page came back empty.
        var oldest: Date?
        /// False once a page comes back short, meaning the archive ends here.
        var hasMore = true
    }

    /// Apps or hosts to leave out, from the PC_EXCLUDE env var (comma separated,
    /// case-insensitive substring match against app name and URL).
    static var exclusions: [String] {
        (ProcessInfo.processInfo.environment["PC_EXCLUDE"] ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    /// One page of the archive, newest first.
    ///
    /// It used to read `ORDER BY timestamp ASC LIMIT 6000`, which is the oldest
    /// six thousand captures — so the window sat at the beginning of the archive
    /// and everything recent fell outside it. On a real archive that meant the
    /// last two days were invisible, and it got worse the more you captured.
    ///
    /// `before` is the cursor: pass the oldest capture you already hold to get
    /// the page behind it.
    static func load(path: String = defaultPath, limit: Int = 1200,
                     before: Date? = nil, raw: Bool = false) -> Load {
        var out = Load()
        guard FileManager.default.fileExists(atPath: path) else {
            out.error = "No archive at \(path)"
            return out
        }
        guard let db = open(path) else {
            out.error = "Could not open the archive"
            return out
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 4000)

        out.meetings = loadMeetings(db)
        for m in out.meetings {
            out.transcripts[m.id] = loadTranscript(db, meetingId: m.id)
        }
        out.uiEventCount = scalar(db, "SELECT COUNT(*) FROM ui_events")
        out.elementCount = scalar(db, "SELECT COUNT(*) FROM elements")
        let page = readFrames(db, limit: limit, before: before)
        out.hasMore = page.count == limit
        out.oldest = page.first?.at
        out.items = assemble(page, meetings: out.meetings, raw: raw)
        out.meetings = out.meetings.map { m in
            guard m.title == nil else { return m }
            // The most common window during a call is whatever you were reading,
            // not the call. Look for the conferencing window itself.
            let during = out.items.filter { $0.meetingId == m.id && !$0.window.isEmpty }
            let callWindows = during.map(\.window).filter { w in
                ["Meet -", "Meet –", "Zoom", "Teams", "FaceTime"].contains { w.contains($0) }
            }
            let top = Dictionary(grouping: callWindows, by: { $0 })
                .max { $0.value.count < $1.value.count }?.key
            return Meeting(id: m.id, start: m.start, end: m.end, app: m.app,
                           title: top.map(cleanMeetingTitle))
        }
        return out
    }

    // MARK: - Frames → moments

    /// A capture as it comes out of the database, before moments are assembled.
    private struct RawFrame {
        let id: Int64
        let at: Date
        let app: String
        let window: String
        let url: String?
        let host: String?
        let snapshot: String?
        let monitor: String?
        let trigger: String
        let textSource: String
        let textLength: Int
        let lines: [String]
        /// Set once the snapshot has been compacted away: the chunk holding this
        /// screen, which frame of it, and the rate it was written at.
        let videoPath: String?
        let videoOffset: Int
        let videoFPS: Double
    }

    /// The join is what makes old screens visible at all. `snapshot_path` only
    /// survives about ten minutes; after that the picture is a frame inside the
    /// chunk this join brings along.
    /// Newest first, so a page is the present rather than the beginning of time.
    /// `before` narrows it to what precedes a cursor, which is how the grid walks
    /// backwards as you scroll.
    private static func framesSQL(before: Bool) -> String {
        """
        SELECT f.id, f.timestamp,
               COALESCE(f.app_name,''), COALESCE(f.window_name,''), COALESCE(f.browser_url,''),
               COALESCE(f.snapshot_path,''), COALESCE(f.device_name,''),
               COALESCE(f.capture_trigger,''), COALESCE(f.text_source,''),
               COALESCE(length(f.full_text),0), COALESCE(f.full_text,''),
               COALESCE(v.file_path,''), COALESCE(f.offset_index,0), COALESCE(v.fps,0)
        FROM frames f
        LEFT JOIN video_chunks v ON v.id = f.video_chunk_id
        \(before ? "WHERE f.timestamp < ?" : "")
        ORDER BY f.timestamp DESC
        LIMIT ?;
        """
    }

    /// A line is furniture when it shows up in many different windows: "Close",
    /// "Inbox", "Recents". A line from your transcript appears in dozens of
    /// captures but in a single window, which is what keeps documents safe.
    private static let furnitureWindowThreshold = 4
    /// Same idea inside one app: the Finder sidebar repeats across every Finder
    /// window, so a lower bar catches app chrome the cross-app rule misses.
    private static let furnitureSameAppThreshold = 3
    /// A window's moment stays open until you have been away from it this long.
    /// Tabbing out to the terminal and back does not start a new conversation.
    private static let momentGap: TimeInterval = 900

    private static func assemble(_ frames: [RawFrame],
                                 meetings: [Meeting], raw: Bool) -> [Photo] {
        guard !frames.isEmpty else { return [] }
        // Raw mode keeps every capture whole — no folding, no furniture removal.
        // It exists so the difference can be seen rather than described.
        let furniture = raw ? Set<String>() : furnitureIndex(frames)
        return assembleMoments(frames, furniture: furniture,
                               meetings: meetings, fold: !raw)
    }

    // MARK: Pass 1 — read

    /// Returns the page in ascending order, which is what folding expects, even
    /// though SQLite hands it over newest first.
    private static func readFrames(_ db: OpaquePointer, limit: Int,
                                   before: Date? = nil) -> [RawFrame] {
        var st: OpaquePointer?
        let sql = framesSQL(before: before != nil)
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        if let before {
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(st, 1, isoString(before), -1, transient)
            sqlite3_bind_int(st, 2, Int32(limit))
        } else {
            sqlite3_bind_int(st, 1, Int32(limit))
        }

        let excl = exclusions
        var out: [RawFrame] = []
        out.reserveCapacity(limit)

        while sqlite3_step(st) == SQLITE_ROW {
            guard let ts = parseDate(text(st, 1)) else { continue }
            let app = text(st, 2)
            let window = text(st, 3)
            let rawURL = text(st, 4)
            let url: String? = rawURL.isEmpty ? nil : rawURL

            if !excl.isEmpty {
                let hay = (app + " " + rawURL + " " + window).lowercased()
                if excl.contains(where: { hay.contains($0) }) { continue }
            }

            let snap = text(st, 5)
            let monitor = text(st, 6)
            let chunk = text(st, 11)
            let fps = sqlite3_column_double(st, 13)
            out.append(RawFrame(
                id: sqlite3_column_int64(st, 0),
                at: ts,
                app: app,
                window: window,
                url: url,
                host: url.flatMap { URL(string: $0)?.host },
                snapshot: snap.isEmpty ? nil : snap,
                monitor: monitor.isEmpty ? nil : monitor,
                trigger: text(st, 7),
                textSource: text(st, 8),
                textLength: Int(sqlite3_column_int64(st, 9)),
                lines: splitLines(text(st, 10)),
                // A chunk with no rate cannot be seeked into, so it counts as no
                // picture rather than as a picture that lands on the wrong screen.
                videoPath: (chunk.isEmpty || fps <= 0) ? nil : chunk,
                videoOffset: Int(sqlite3_column_int64(st, 12)),
                videoFPS: fps
            ))
        }
        // SQLite handed these over newest first; folding walks time forwards.
        out.reverse()
        return out
    }

    private static func splitLines(_ raw: String) -> [String] {
        raw.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 2 }
    }

    // MARK: Pass 2 — what is furniture

    private static func furnitureIndex(_ frames: [RawFrame]) -> Set<String> {
        var windowsPerLine: [String: Set<String>] = [:]
        var appWindowsPerLine: [String: Set<String>] = [:]
        for f in frames {
            let windowKey = f.app + "\u{1}" + f.window
            for line in Set(f.lines) {
                windowsPerLine[line, default: []].insert(windowKey)
                appWindowsPerLine[line, default: []].insert(f.app + "\u{1}" + f.window)
            }
        }
        var furniture: Set<String> = []
        for (line, windows) in windowsPerLine {
            let apps = Set(windows.map { $0.split(separator: "\u{1}").first.map(String.init) ?? "" })
            if windows.count >= furnitureWindowThreshold && apps.count > 1 {
                furniture.insert(line)                      // seen across apps
            } else if windows.count >= furnitureSameAppThreshold && apps.count == 1 {
                furniture.insert(line)                      // app chrome, e.g. Finder sidebar
            }
        }
        return furniture
    }

    // MARK: Pass 3 — assemble moments

    /// One moment stays open per window rather than per consecutive run. Alt-tabbing
    /// to the terminal and back continues the same conversation instead of starting
    /// a new one — which is how people remember it, and it halves the moment count.
    private final class OpenMoment {
        let first: RawFrame
        var lastAt: Date
        var captures = 0
        var rawLines = 0
        var seen: Set<String> = []
        var content: [String] = []
        var snapshot: String?
        /// Every screen of this moment that can still be shown, in order.
        var shots: [Shot] = []
        /// How many captures each trigger accounts for, so the inspector can say
        /// "mostly you paused typing" instead of quoting the first frame.
        var triggers: [String: Int] = [:]
        init(_ f: RawFrame) {
            first = f
            lastAt = f.at
            snapshot = f.snapshot
        }

        func take(_ f: RawFrame) {
            if !f.trigger.isEmpty { triggers[f.trigger, default: 0] += 1 }
            guard f.snapshot != nil || f.videoPath != nil else { return }
            shots.append(Shot(frameId: f.id, at: f.at, jpgPath: f.snapshot,
                              videoPath: f.videoPath, offset: f.videoOffset,
                              fps: f.videoFPS))
        }
    }

    private static func assembleMoments(_ frames: [RawFrame],
                                        furniture: Set<String>,
                                        meetings: [Meeting],
                                        fold: Bool) -> [Photo] {
        var out: [Photo] = []
        var open: [String: OpenMoment] = [:]

        func close(_ m: OpenMoment) {
            let f = m.first
            let meetingId = meetings.first { $0.contains(f.at) }?.id
            let kind = classify(app: f.app, host: f.host, window: f.window,
                                inMeeting: meetingId != nil)
            out.append(Photo(
                id: UUID(), frameId: f.id, date: f.at, app: f.app, window: f.window,
                url: f.url, host: f.host, snapshotPath: m.snapshot,
                shots: m.shots, triggers: m.triggers,
                excerpt: m.content.prefix(60).joined(separator: "\n"),
                textLength: f.textLength, source: kind, captureTrigger: f.trigger,
                textSource: f.textSource, monitor: f.monitor, meetingId: meetingId,
                repeatCount: m.captures, lastSeen: m.lastAt,
                rawLineCount: m.rawLines, contentLineCount: m.content.count,
                substantiveLineCount: m.content.count { $0.count >= 25 },
                isFavorite: false, isDeleted: false, isHidden: false
            ))
        }

        for f in frames {
            // Raw mode gives every capture its own key, so nothing ever merges.
            // The display is part of the key: with two monitors the engine writes
            // one row per screen at the same instant, both carrying the focused
            // window's text. Folding them together produced a moment whose picture
            // was one display and whose text was the window on the other.
            let key = fold ? f.app + "\u{1}" + f.window + "\u{1}" + (f.monitor ?? "") : String(f.id)
            var moment = open[key]
            if let m = moment, f.at.timeIntervalSince(m.lastAt) > momentGap {
                close(m)
                moment = nil
            }
            let m = moment ?? OpenMoment(f)
            open[key] = m

            m.captures += 1
            m.rawLines += f.lines.count
            m.lastAt = f.at
            m.take(f)
            if m.snapshot == nil { m.snapshot = f.snapshot }
            // The union of everything that passed through, in order of first sight.
            // Right for a chat where messages arrive and for a document that just sits.
            for line in f.lines where !m.seen.contains(line) {
                m.seen.insert(line)
                if !furniture.contains(line) { m.content.append(line) }
            }
        }
        for m in open.values { close(m) }
        return out.sorted { $0.date < $1.date }
    }

    /// App + host → surface. Deliberately simple and legible: this is the kind of
    /// rule the engine could persist instead of recomputing at read time.
    static func classify(app: String, host: String?, window: String, inMeeting: Bool) -> ContextSource {
        let a = app.lowercased()
        let h = (host ?? "").lowercased()
        if inMeeting || h.contains("meet.google") || h.contains("zoom.us") || h.contains("teams.") {
            return .meeting
        }
        if h.contains("whatsapp") || h.contains("slack") || h.contains("discord")
            || h.contains("telegram") || a.contains("messages") || a.contains("slack") {
            return .chat
        }
        if a.contains("superhuman") || a.contains("mail") || h.contains("mail.google")
            || h.contains("outlook") { return .email }
        if a.contains("terminal") || a.contains("iterm") || a.contains("warp") { return .terminal }
        if a.contains("code") || a.contains("xcode") || a.contains("cursor")
            || a.contains("zed") || h.contains("github.com") { return .editor }
        if a.contains("figma") || a.contains("sketch") || a.contains("photos") { return .design }
        if a.contains("textedit") || a.contains("notes") || a.contains("obsidian")
            || a.contains("pages") { return .notes }
        if a.contains("finder") { return .files }
        if host != nil || a.contains("chrome") || a.contains("safari") || a.contains("arc")
            || a.contains("firefox") { return .browser }
        return .other
    }

    // MARK: - Full-text search

    /// Keyword search over the whole captured text, not just the excerpt we hold in
    /// memory. Uses the engine's own FTS5 index, so it reaches into the 40k-character
    /// tail of a terminal buffer or the middle of a chat pane.
    /// Returns frame id → the matching sentence, so the UI can show *why* it matched.
    static func search(_ query: String, path: String = defaultPath, limit: Int = 400) -> [Int64: String] {
        let terms = query.trimmingCharacters(in: .whitespaces)
        guard terms.count >= 2 else { return [:] }
        guard let db = open(path) else { return [:] }
        defer { sqlite3_close(db) }

        // Quote each word and add a prefix wildcard, so "climb" also matches "climbing".
        let match = terms.split(separator: " ")
            .map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\"*" }
            .joined(separator: " ")

        let sql = """
        SELECT rowid, snippet(frames_fts, 0, '', '', '…', 18)
        FROM frames_fts WHERE frames_fts MATCH ? ORDER BY rank LIMIT ?;
        """
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, (match as NSString).utf8String, -1, nil)
        sqlite3_bind_int(st, 2, Int32(limit))

        var out: [Int64: String] = [:]
        while sqlite3_step(st) == SQLITE_ROW {
            out[sqlite3_column_int64(st, 0)] = cleanExcerpt(text(st, 1))
        }
        return out
    }

    // MARK: - Meetings

    private static func loadMeetings(_ db: OpaquePointer) -> [Meeting] {
        let sql = """
        SELECT id, meeting_start, COALESCE(meeting_end,''), COALESCE(meeting_app,''),
               COALESCE(title,'')
        FROM meetings ORDER BY meeting_start ASC;
        """
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        var out: [Meeting] = []
        while sqlite3_step(st) == SQLITE_ROW {
            guard let start = parseDate(text(st, 1)) else { continue }
            let title = text(st, 4)
            out.append(Meeting(id: sqlite3_column_int64(st, 0),
                               start: start,
                               end: parseDate(text(st, 2)),
                               app: text(st, 3),
                               title: title.isEmpty ? nil : title))
        }
        return out
    }

    private static func loadTranscript(_ db: OpaquePointer, meetingId: Int64) -> [TranscriptLine] {
        let sql = """
        SELECT id, captured_at, COALESCE(speaker_name,''), COALESCE(device_type,''),
               COALESCE(transcript,'')
        FROM meeting_transcript_segments
        WHERE meeting_id = ? ORDER BY captured_at ASC;
        """
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_int64(st, 1, meetingId)
        var out: [TranscriptLine] = []
        while sqlite3_step(st) == SQLITE_ROW {
            let body = text(st, 4).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty, !isHallucination(body) else { continue }
            let device = text(st, 3).lowercased()
            let isMe = device.contains("input")
            let named = text(st, 2)
            out.append(TranscriptLine(
                id: sqlite3_column_int64(st, 0),
                at: parseDate(text(st, 1)) ?? .distantPast,
                speaker: named.isEmpty ? (isMe ? "You" : "Them") : named,
                isMe: isMe,
                text: body
            ))
        }
        return out
    }

    /// Whisper was trained on video subtitles, so on silence it emits the phrases
    /// that end videos — "Thank you.", "See you in the next video" — often in
    /// Korean, Japanese or Russian regardless of what language was spoken. Roughly
    /// 8% of the segments in this archive are that. They are noise, not speech.
    static func isHallucination(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= 3 { return true }
        let fillers: Set<String> = ["thank you.", "thank you", "thanks.", "okay.", "ok.",
                                    "bye.", "you", "bye bye.", "so.", ".", "..."]
        if fillers.contains(t.lowercased()) { return true }
        // A segment written in a script nobody in the call was speaking.
        let foreign = t.unicodeScalars.filter { s in
            (0xAC00...0xD7AF).contains(s.value)      // Hangul
                || (0x4E00...0x9FFF).contains(s.value)   // CJK
                || (0x3040...0x30FF).contains(s.value)   // Kana
                || (0x0400...0x04FF).contains(s.value)   // Cyrillic
        }.count
        return foreign > 0 && Double(foreign) / Double(t.unicodeScalars.count) > 0.3
    }

    /// "Meet - Jumpstart Checkpoint (Rafael Costa) - Micro..." → "Jumpstart Checkpoint"
    static func cleanMeetingTitle(_ window: String) -> String {
        var t = window
        for prefix in ["Meet - ", "Zoom - ", "Teams - "] where t.hasPrefix(prefix) {
            t = String(t.dropFirst(prefix.count))
        }
        if let paren = t.firstIndex(of: "(") { t = String(t[t.startIndex..<paren]) }
        if let dash = t.range(of: " - ") { t = String(t[t.startIndex..<dash.lowerBound]) }
        return t.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Helpers

    private static func scalar(_ db: OpaquePointer, _ sql: String) -> Int {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(st) }
        return sqlite3_step(st) == SQLITE_ROW ? Int(sqlite3_column_int64(st, 0)) : 0
    }

    private static func text(_ st: OpaquePointer?, _ col: Int32) -> String {
        guard let c = sqlite3_column_text(st, col) else { return "" }
        return String(cString: c)
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    static func parseDate(_ s: String) -> Date? {
        if s.isEmpty { return nil }
        return isoFractional.date(from: s) ?? isoPlain.date(from: s)
    }

    /// The cursor for paging, written the way the column stores it. The engine
    /// writes fractional seconds, and SQLite compares these as text, so the
    /// format has to match or the comparison walks off.
    static func isoString(_ d: Date) -> String { isoFractional.string(from: d) }

    /// The accessibility walker already separates every element with a newline, so
    /// the text arrives structured — conversation, time, sender, message, one per
    /// line. Keep those breaks. Only collapse the noise: blank lines, one-character
    /// fragments, and the immediate repeats the AX tree emits for a label and its
    /// container ("Toutes" / "Toutes").
    private static func cleanExcerpt(_ raw: String) -> String {
        var lines: [String] = []
        for piece in raw.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = piece.trimmingCharacters(in: .whitespaces)
            if line.count < 2 { continue }
            if line == lines.last { continue }
            lines.append(line)
            if lines.count >= 40 { break }
        }
        // OCR frames come back as one glued run with no breaks; nothing to structure.
        return String(lines.joined(separator: "\n").prefix(700))
    }
}
