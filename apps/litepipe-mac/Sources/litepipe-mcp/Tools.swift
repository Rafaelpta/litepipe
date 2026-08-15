import Foundation
import SQLite3

/// The questions an agent may ask the archive.
///
/// Six tools, all read only. Five of them are the paths a person actually asks
/// about (find this, what happened that day, which meetings, what was said, what
/// surrounded this moment); the sixth hands over SQL, because no fixed set of
/// tools survives contact with a real question. "Which terminal windows came back
/// most often this week, grouped by project" is not a search, and pretending it
/// is produces a worse answer than letting the model write the query.
enum Tools {

    struct Tool {
        let name: String
        /// What a client shows a person picking a tool from a list. The name is for
        /// the model and stays in snake case; this is the sentence a human reads.
        let title: String
        let description: String
        let schema: [String: Any]
        let run: ([String: Any]) throws -> String
    }

    /// Answers are clipped, hard. A tool that returns a day of screen text buries
    /// the question in its own evidence and costs the person a fortune in their
    /// own context window.
    static let maxChars = 12000

    static let all: [Tool] = [searchContent, activitySummary, listMeetings,
                              meetingTranscript, frameContext, rawQuery]

    static let byName: [String: Tool] = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })

    /// Every tool here reads and nothing else. Saying so in the fields a client can
    /// check, rather than only in a README, is what lets a careful client mark this
    /// server safe without anyone taking our word for it.
    ///
    /// `openWorldHint` is false because the archive is a closed domain: one file on
    /// this disk. There is no third party for a call to reach.
    private static let readOnly: [String: Any] = [
        "readOnlyHint": true,
        "destructiveHint": false,
        "idempotentHint": true,
        "openWorldHint": false,
    ]

    static var manifest: [[String: Any]] {
        all.map {
            ["name": $0.name,
             "title": $0.title,
             "description": $0.description,
             "inputSchema": $0.schema,
             "annotations": readOnly]
        }
    }

    // MARK: Tools

    /// Goes through the same FTS index the window's search box uses, so a hit here
    /// is a hit there.
    private static let searchContent = Tool(
        name: "search_content",
        title: "Search the archive",
        description: """
            Full text search over everything captured on screen. Returns the moments \
            that matched, newest first, with the sentence that matched and where it \
            came from. Use this to find something; use query to count or group.
            """,
        schema: object([
            "query": string("Words to look for. Each word also matches longer words starting with it."),
            "limit": integer("How many moments to return. Default 25, maximum 100."),
            "since": string("Optional ISO date or datetime. Only moments at or after it."),
            "until": string("Optional ISO date or datetime. Only moments before it."),
        ], required: ["query"])
    ) { args in
        let q = try str(args, "query")
        let limit = min(int(args, "limit") ?? 25, 100)
        // Ask the index for more than is wanted: the date filter and the cap are
        // applied after, and a narrow window would otherwise come back empty.
        let hits = ContextDB.search(q, limit: 400)
        guard !hits.isEmpty else { return "Nothing in the archive matches \(q)." }

        var sql = """
        SELECT f.id, f.timestamp, COALESCE(f.app_name,''), COALESCE(f.window_name,''),
               COALESCE(f.browser_url,'')
        FROM frames f WHERE f.id IN (\(hits.keys.map(String.init).joined(separator: ",")))
        """
        var binds: [String] = []
        if let since = args["since"] as? String { sql += " AND datetime(f.timestamp) >= datetime(?)"; binds.append(since) }
        if let until = args["until"] as? String { sql += " AND datetime(f.timestamp) < datetime(?)"; binds.append(until) }
        sql += " ORDER BY f.timestamp DESC LIMIT \(limit);"

        let rows = try Archive.rows(sql, binds)
        guard !rows.isEmpty else { return "\(hits.count) matches, none inside that time range." }

        // The index was asked for 400 and gave 400, so 400 is the ceiling and not
        // the answer. Printing it as a count teaches the model a wrong number and
        // it will repeat it to whoever asked.
        let matched = hits.count >= 400 ? "At least 400" : "\(hits.count)"
        var out = "\(matched) moments match. Showing \(rows.count), newest first.\n\n"
        for r in rows {
            let id = r[0]
            out += "[\(r[1])] \(r[2])"
            if !r[3].isEmpty { out += " — \(r[3])" }
            if !r[4].isEmpty { out += " (\(r[4]))" }
            out += "\n"
            if let snippet = hits[Int64(id) ?? -1], !snippet.isEmpty { out += "    \(snippet)\n" }
            out += "    frame \(id)\n"
        }
        return out
    }

    /// What a day looked like, without reading the day.
    private static let activitySummary = Tool(
        name: "activity_summary",
        title: "Summarise a day",
        description: """
            Where the time went on a given day: which apps, for how long, how many \
            captures each, and any meetings. Start here for "what did I do" questions \
            before pulling any text.
            """,
        schema: object([
            "date": string("Day to summarise, YYYY-MM-DD. Defaults to the most recent day with captures."),
        ], required: [])
    ) { args in
        let day: String
        if let d = args["date"] as? String { day = String(d.prefix(10)) }
        else {
            day = try Archive.rows("SELECT date(MAX(timestamp)) FROM frames;", []).first?.first ?? ""
        }
        guard !day.isEmpty else { return "The archive is empty." }

        let apps = try Archive.rows("""
            SELECT COALESCE(app_name,'(unknown)'), COUNT(*),
                   MIN(time(timestamp)), MAX(time(timestamp))
            FROM frames WHERE date(timestamp) = ?
            GROUP BY 1 ORDER BY 2 DESC LIMIT 15;
            """, [day])
        guard !apps.isEmpty else { return "Nothing was captured on \(day)." }

        let total = try Archive.rows("SELECT COUNT(*), MIN(time(timestamp)), MAX(time(timestamp)) FROM frames WHERE date(timestamp) = ?;", [day]).first
        var out = "\(day): \(total?[0] ?? "?") captures between \(total?[1] ?? "?") and \(total?[2] ?? "?") UTC.\n\n"
        out += "app\tcaptures\tfirst\tlast\n"
        for a in apps { out += "\(a[0])\t\(a[1])\t\(a[2])\t\(a[3])\n" }

        let meetings = try Archive.rows("""
            SELECT id, COALESCE(meeting_app,''), time(meeting_start), COALESCE(time(meeting_end),'')
            FROM meetings WHERE date(meeting_start) = ? ORDER BY meeting_start;
            """, [day])
        if !meetings.isEmpty {
            out += "\nmeetings:\n"
            for m in meetings { out += "  \(m[2])–\(m[3]) \(m[1]) (meeting \(m[0]))\n" }
        }
        return out
    }

    private static let listMeetings = Tool(
        name: "list_meetings",
        title: "List meetings",
        description: "Meetings detected from audio, newest first, with how much was transcribed.",
        schema: object(["limit": integer("How many. Default 20.")], required: [])
    ) { args in
        let limit = min(int(args, "limit") ?? 20, 100)
        let rows = try Archive.rows("""
            SELECT m.id, m.meeting_start, COALESCE(m.meeting_end,''), COALESCE(m.meeting_app,''),
                   (SELECT COUNT(*) FROM meeting_transcript_segments s WHERE s.meeting_id = m.id)
            FROM meetings m ORDER BY m.meeting_start DESC LIMIT \(limit);
            """, [])
        guard !rows.isEmpty else { return "No meetings in the archive." }
        var out = "meeting_id\tstart\tend\tapp\tsegments\n"
        for r in rows { out += r.joined(separator: "\t") + "\n" }
        out += "\nUse meeting_transcript with a meeting_id to read one."
        return out
    }

    private static let meetingTranscript = Tool(
        name: "meeting_transcript",
        title: "Read a meeting transcript",
        description: "The transcript of one meeting, in order, with speakers and times. "
                   + "Unnamed voices come back numbered, which is what diarisation "
                   + "produces until somebody names them.",
        schema: object(["meeting_id": integer("From list_meetings.")], required: ["meeting_id"])
    ) { args in
        guard let id = int(args, "meeting_id") else { throw Err("meeting_id is required.") }
        // This is the one table that does not follow the `timestamp` convention the
        // rest of the archive uses, and asking for the convention rather than the
        // column made every call fail with `no such column: timestamp`.
        //
        // speaker_name is written by whoever named the voice, which is nobody so
        // far, so the id is the only identity that exists and the fallback carries
        // it rather than printing the same '?' against four different people.
        let rows = try Archive.rows("""
            SELECT time(captured_at),
                   COALESCE(NULLIF(speaker_name,''), 'speaker ' || speaker_id, '?'),
                   COALESCE(transcript,'')
            FROM meeting_transcript_segments WHERE meeting_id = ? ORDER BY captured_at;
            """, [String(id)])
        guard !rows.isEmpty else { return "Meeting \(id) has no transcript." }
        var out = ""
        for r in rows where !r[2].isEmpty { out += "[\(r[0])] \(r[1]): \(r[2])\n" }
        return out
    }

    /// A search hit is a sentence with no surroundings. This is how the model
    /// gets the rest of the screen, and what came before and after it.
    private static let frameContext = Tool(
        name: "frame_context",
        title: "Open a moment",
        description: """
            Everything captured in one moment, plus the captures immediately before \
            and after it. Use it on a frame id returned by search_content.
            """,
        schema: object([
            "frame_id": integer("From search_content."),
            "neighbours": integer("How many captures either side. Default 2, maximum 10."),
        ], required: ["frame_id"])
    ) { args in
        guard let id = int(args, "frame_id") else { throw Err("frame_id is required.") }
        let n = min(int(args, "neighbours") ?? 2, 10)
        let centre = try Archive.rows("""
            SELECT timestamp, COALESCE(app_name,''), COALESCE(window_name,''),
                   COALESCE(browser_url,''), COALESCE(NULLIF(full_text,''), COALESCE(accessibility_text,''))
            FROM frames WHERE id = ?;
            """, [String(id)])
        guard let c = centre.first else { throw Err("No frame with id \(id).") }

        var out = "frame \(id) — \(c[0])\n\(c[1])"
        if !c[2].isEmpty { out += " — \(c[2])" }
        if !c[3].isEmpty { out += "\n\(c[3])" }
        out += "\n\n\(c[4])\n"

        let around = try Archive.rows("""
            SELECT id, timestamp, COALESCE(app_name,''), COALESCE(window_name,'')
            FROM frames WHERE timestamp BETWEEN datetime(?, '-5 minutes') AND datetime(?, '+5 minutes')
              AND id <> ? ORDER BY ABS(strftime('%s', timestamp) - strftime('%s', ?)) LIMIT \(n * 2);
            """, [c[0], c[0], String(id), c[0]])
        if !around.isEmpty {
            out += "\naround it:\n"
            for r in around { out += "  frame \(r[0]) [\(r[1])] \(r[2]) \(r[3])\n" }
        }
        return out
    }

    /// The tool that makes the rest of them optional.
    private static let rawQuery = Tool(
        name: "query",
        title: "Query the archive with SQL",
        description: """
            Read only SQL over the archive. SELECT statements only; a LIMIT is added \
            if you leave one out. Timestamps are UTC ISO 8601: compare with \
            datetime(timestamp) and group with date(timestamp).

            frames(id, timestamp, app_name, window_name, browser_url, full_text, \
            accessibility_text, capture_trigger, text_source, document_path, \
            video_chunk_id, offset_index) is one row per captured moment.

            elements(id, frame_id, source, role, text, parent_id, depth, left_bound, \
            top_bound, width_bound, height_bound, confidence, sort_order, properties, \
            on_screen) is every piece of text on that screen as its own row, with \
            where it sat: the bounds are 0 to 1, top_bound 0 is the top of the screen. \
            source is 'accessibility' or 'ocr'. This is how you read a layout rather \
            than a page of text: rows near each other in top_bound were near each \
            other on screen, so the line under a heading, or the message under a name \
            in a sidebar, is found by joining elements to itself on a small top_bound \
            difference within one frame. Chat apps that expose only a conversation \
            list are readable this way and no other.

            audio_transcriptions(id, audio_chunk_id, timestamp, transcription, device, \
            is_input_device, speaker_id, transcription_engine, start_time, end_time) \
            is what was heard, with speaker_id joining speakers(id, name).

            ui_events(id, timestamp, event_type, text_content, app_name, window_title, \
            browser_url, element_role, element_name, frame_id) is what was typed, \
            clicked and copied; event_type includes 'text', 'click', 'clipboard'.

            Also ocr_text(frame_id, text), meetings(id, meeting_start, meeting_end, \
            meeting_app, title), video_chunks(id, file_path, fps).

            meeting_transcript_segments(meeting_id, captured_at, speaker_name, \
            transcript, speaker_id) is the one table that does not name its time \
            column `timestamp`: it is `captured_at`. speaker_name is usually empty \
            and speaker_id is what identifies a voice.
            """,
        schema: object(["sql": string("A single SELECT statement.")], required: ["sql"])
    ) { args in
        var sql = try str(args, "sql").trimmingCharacters(in: .whitespacesAndNewlines)
        while sql.hasSuffix(";") { sql.removeLast() }
        let lower = sql.lowercased()
        guard lower.hasPrefix("select") || lower.hasPrefix("with") else {
            throw Err("query runs SELECT statements only.")
        }
        // The connection is opened read only, so this is a second lock on a door
        // that is already locked: it turns a silent SQLite error into a sentence
        // the model can act on.
        for word in ["insert ", "update ", "delete ", "drop ", "alter ", "create ",
                     "attach ", "pragma ", "vacuum ", "replace "] where lower.contains(word) {
            throw Err("query is read only and cannot \(word.trimmingCharacters(in: .whitespaces)).")
        }
        if !lower.contains("limit") { sql += " LIMIT 100" }

        let rows = try Archive.rows(sql, [], withHeader: true)
        guard rows.count > 1 else { return "No rows." }
        return rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
    }

    // MARK: Schema helpers

    private static func object(_ props: [String: Any], required: [String]) -> [String: Any] {
        ["type": "object", "properties": props, "required": required]
    }
    private static func string(_ d: String) -> [String: Any] { ["type": "string", "description": d] }
    private static func integer(_ d: String) -> [String: Any] { ["type": "integer", "description": d] }

    private static func str(_ a: [String: Any], _ k: String) throws -> String {
        guard let v = a[k] as? String, !v.isEmpty else { throw Err("\(k) is required.") }
        return v
    }
    private static func int(_ a: [String: Any], _ k: String) -> Int? {
        if let i = a[k] as? Int { return i }
        if let d = a[k] as? Double { return Int(d) }
        if let s = a[k] as? String { return Int(s) }
        return nil
    }
}

struct Err: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

/// A read only connection per call. Opening costs under a millisecond and the
/// alternative is holding a handle open across a session that may idle for hours
/// while the engine writes underneath it.
enum Archive {
    static func rows(_ sql: String, _ binds: [String], withHeader: Bool = false) throws -> [[String]] {
        // Through the window's opener, which knows the one case where asking for
        // read only makes the archive unreadable: a WAL database with nobody else
        // holding it open, which is exactly the state an agent asks in.
        guard let db = ContextDB.open() else {
            throw Err("Could not open the archive at \(ContextDB.defaultPath). Open litepipe once to create it.")
        }
        defer { sqlite3_close(db) }

        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK, let st else {
            let why = String(cString: sqlite3_errmsg(db))
            // Reading a WAL database needs a shared memory file beside it, so a
            // folder nobody may write to cannot be read either. SQLite reports
            // that as a write error, which reads like a bug in a read only tool.
            if why.contains("readonly") {
                throw Err("The archive folder is not writable, and reading this database needs to place a lock file beside it. Nothing is being written to the archive itself.")
            }
            throw Err(why)
        }
        defer { sqlite3_finalize(st) }
        for (i, b) in binds.enumerated() {
            sqlite3_bind_text(st, Int32(i + 1), (b as NSString).utf8String, -1, nil)
        }

        var out: [[String]] = []
        let cols = Int(sqlite3_column_count(st))
        if withHeader {
            out.append((0..<cols).map { String(cString: sqlite3_column_name(st, Int32($0))) })
        }
        var size = 0
        while sqlite3_step(st) == SQLITE_ROW {
            var row: [String] = []
            for c in 0..<cols {
                let v = sqlite3_column_text(st, Int32(c)).map { String(cString: $0) } ?? ""
                // Screen text arrives with its own line breaks, which would turn one
                // row into twenty and make the result unreadable as a table.
                row.append(v.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " "))
            }
            size += row.reduce(0) { $0 + $1.count }
            if size > Tools.maxChars {
                out.append(["… truncated at \(Tools.maxChars) characters, narrow the query for more"])
                break
            }
            out.append(row)
        }
        return out
    }
}
