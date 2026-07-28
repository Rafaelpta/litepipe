import AppKit
import Combine
import SQLite3

// Watches on-screen window titles for meeting apps (Meet, Zoom, Teams, FaceTime)
// and drives the meeting lifecycle around the engine's API:
//   suspected -> user confirms via the prompt banner -> POST /meetings/start
//   (engine flag flips -> the mic gate in EngineController turns the mic on)
//   meeting windows gone for ~60s -> POST /meetings/stop -> delayed retranscribe
//   with the strong model -> mic audio files deleted (voice becomes text only).
// Title matching is deliberately the detection mechanism: it needs only the
// Screen Recording permission the app already holds, and window titles do not
// depend on the accessibility tree being materialized.
final class MeetingWatcher: ObservableObject {
    @Published private(set) var suspected = false
    @Published private(set) var suspectedAppName: String?
    @Published private(set) var suspectedServiceName: String?
    @Published private(set) var suspectedAppIcon: NSImage?
    @Published private(set) var transcribing = false

    private static let serviceNames = [
        "meet": "Google Meet", "zoom": "Zoom", "teams": "Teams", "facetime": "FaceTime",
    ]

    private let engine: EngineController
    private var timer: Timer?
    private var positiveStreak = 0
    private var negativeStreak = 0
    private var dismissedUntilClear = false
    private var meetingId: Int?
    private var cleanupTimer: Timer?
    private var lastTitleDiag = Date.distantPast
    private let dataDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".litepipe", isDirectory: true)

    init(engine: EngineController) {
        self.engine = engine
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.scan() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        scan()
        let c = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in self?.cleanupAudioFiles() }
        RunLoop.main.add(c, forMode: .common)
        cleanupTimer = c
    }

    func stop() {
        timer?.invalidate(); timer = nil
        cleanupTimer?.invalidate(); cleanupTimer = nil
    }

    // MARK: - Detection (window titles)

    private struct Match { let app: String; let pid: pid_t; let service: String }

    private func findMeetingWindow() -> Match? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return nil }
        for w in list {
            guard let owner = w[kCGWindowOwnerName as String] as? String,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t else { continue }
            let title = (w[kCGWindowName as String] as? String) ?? ""
            let t = title.lowercased()
            let o = owner.lowercased()

            // Google Meet in any browser: the tab window is titled "Meet – xyz".
            if t.hasPrefix("meet – ") || t.hasPrefix("meet - ") || t.hasPrefix("meet —") {
                return Match(app: owner, pid: pid, service: "meet")
            }
            // Zoom web client titles vary (topic, "Zoom", "Meeting - Zoom");
            // be generous — the banner's No button makes false positives cheap.
            if t.contains("zoom") {
                return Match(app: owner, pid: pid, service: "zoom")
            }
            if o.contains("zoom.us"), !t.isEmpty {
                return Match(app: owner, pid: pid, service: "zoom")
            }
            if o.contains("microsoft teams"), t.contains("meeting") || t.contains("call") {
                return Match(app: owner, pid: pid, service: "teams")
            }
            if o == "facetime", !t.isEmpty {
                return Match(app: owner, pid: pid, service: "facetime")
            }
        }
        // Titles are the meeting TOPIC on web clients ("Ma réunion") — fall back
        // to the browser URL the engine already captures with each frame.
        if let m = matchFromRecentFrameURLs() { return m }
        // No match: leave a breadcrumb of what the browser windows were called,
        // so a missed meeting explains itself (rate limited to every 5 min).
        if Date().timeIntervalSince(lastTitleDiag) > 300 {
            lastTitleDiag = Date()
            let titles = list.compactMap { w -> String? in
                guard let o = (w[kCGWindowOwnerName as String] as? String)?.lowercased(),
                      o.contains("chrome") || o.contains("safari") || o.contains("arc") || o.contains("edge"),
                      let t = w[kCGWindowName as String] as? String, !t.isEmpty else { return nil }
                return t
            }
            if !titles.isEmpty {
                litepipeLog("meeting scan: no match; browser titles=\(titles.prefix(4))")
            }
        }
        return nil
    }

    // The engine stamps the focused browser window's URL onto captured frames;
    // a recent frame on a meeting domain is a solid signal regardless of title.
    private func matchFromRecentFrameURLs() -> Match? {
        var db: OpaquePointer?
        let path = dataDir.appendingPathComponent("db.sqlite").path
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }
        let sql = """
            SELECT browser_url, app_name FROM frames
            WHERE timestamp > datetime('now','-30 seconds') AND browser_url IS NOT NULL
            ORDER BY id DESC LIMIT 10
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        let domains: [(String, String)] = [
            ("zoom.us", "zoom"), ("meet.google.com", "meet"), ("teams.microsoft", "teams"),
        ]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let u = sqlite3_column_text(stmt, 0) else { continue }
            let url = String(cString: u).lowercased()
            let app = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "browser"
            for (domain, service) in domains where url.contains(domain) {
                // zoom.us matches the whole site; require the meeting client path.
                if service == "zoom", !url.contains("/wc/"), !url.contains("/j/") { continue }
                return Match(app: app, pid: 0, service: service)
            }
        }
        return nil
    }

    private func scan() {
        let match = findMeetingWindow()
        if let match {
            positiveStreak += 1
            negativeStreak = 0
            if positiveStreak >= 2, !suspected, !transcribing, !dismissedUntilClear {
                suspectedAppName = match.app
                suspectedServiceName = Self.serviceNames[match.service]
                // The banner shows the meeting SERVICE's logo (Meet/Zoom/Teams),
                // not the browser's; the app icon is the fallback.
                let bundled = Bundle.main.url(forResource: match.service, withExtension: "png",
                                              subdirectory: "servicelogos")
                    .flatMap { NSImage(contentsOf: $0) }
                suspectedAppIcon = bundled ?? NSRunningApplication(processIdentifier: match.pid)?.icon
                suspected = true
            }
        } else {
            negativeStreak += 1
            positiveStreak = 0
            dismissedUntilClear = false
            if suspected, negativeStreak >= 4 { // ~20s without a meeting window
                suspected = false
            }
            if transcribing, negativeStreak >= 12 { // ~60s: the call really ended
                stopTranscribing()
            }
        }
    }

    // MARK: - Lifecycle (driven by the prompt banner / notch panel)

    func accept() {
        suspected = false
        startTranscribing()
    }

    func decline() {
        suspected = false
        dismissedUntilClear = true // don't re-prompt until the meeting window goes away
    }

    func startTranscribing() {
        guard !transcribing else { return }
        transcribing = true
        litepipeLog("meeting: start requested app=\(suspectedAppName ?? "?")")
        // A confirmed meeting outranks a paused capture: wake the engine if
        // needed, then keep knocking until its API is up (cold start takes a
        // while) before registering the meeting.
        if engine.status != .recording, engine.status != .starting {
            engine.togglePause(source: "meeting-start")
        }
        attemptStart(retriesLeft: 15)
    }

    private func attemptStart(retriesLeft: Int) {
        guard transcribing else { return } // user stopped meanwhile
        engine.engineAPI("meetings/start", method: "POST",
                         body: ["app": suspectedAppName ?? "meeting"]) { [weak self] json in
            guard let self else { return }
            if let obj = json as? [String: Any], let id = obj["id"] as? Int {
                self.meetingId = id
                litepipeLog("meeting: registered id=\(id)")
            } else if let obj = json as? [String: Any], obj["error"] != nil {
                // e.g. 409: a meeting is already active; adopt it.
                self.engine.engineAPI("meetings/status", method: "GET", body: nil) { st in
                    self.meetingId = (st as? [String: Any])?["active_meeting_id"] as? Int
                }
            } else if retriesLeft > 0 {
                // engine API not up yet
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    self?.attemptStart(retriesLeft: retriesLeft - 1)
                }
            } else {
                litepipeLog("meeting: start FAILED (engine api never came up)")
                self.transcribing = false
            }
        }
    }

    func stopTranscribing() {
        guard transcribing else { return }
        transcribing = false
        litepipeLog("meeting: stop id=\(meetingId.map(String.init) ?? "?")")
        let id = meetingId
        engine.engineAPI("meetings/stop", method: "POST", body: [:]) { _ in }
        // Full-context quality pass. The engine refuses chunks younger than 10
        // minutes (reconciliation freshness floor), so the pass waits them out.
        DispatchQueue.main.asyncAfter(deadline: .now() + 660) { [weak self] in
            self?.retranscribe(id: id)
        }
    }

    private func retranscribe(id: Int?) {
        let engineName = UserDefaults.standard.string(forKey: "transcription.engine")
            ?? "whisper-large-v3-turbo-quantized"
        let fire: (Int) -> Void = { [weak self] mid in
            self?.engine.engineAPI("meetings/\(mid)/retranscribe", method: "POST",
                                   body: ["engine": engineName]) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 120) {
                    self?.cleanupAudioFiles()
                }
            }
        }
        if let id { fire(id); return }
        engine.engineAPI("meetings?limit=1", method: "GET", body: nil) { json in
            var rows = json as? [[String: Any]]
            if rows == nil, let obj = json as? [String: Any] {
                rows = obj["meetings"] as? [[String: Any]]
            }
            if let mid = rows?.first?["id"] as? Int { fire(mid) }
        }
    }

    // MARK: - Audio becomes text (privacy sweep)

    // Voice never outlives its transcription: transcribed mic chunks older than
    // 15 minutes lose their audio file; system audio is kept for 7 days. Rows
    // stay in the engine's DB (the text is the product), only files go.
    func cleanupAudioFiles() {
        DispatchQueue.global(qos: .utility).async { [dataDir] in
            var db: OpaquePointer?
            let path = dataDir.appendingPathComponent("db.sqlite").path
            guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return }
            defer { sqlite3_close(db) }
            let sql = """
                SELECT file_path FROM audio_chunks
                WHERE transcription_status = 'transcribed'
                  AND ((file_path LIKE '%(input)%'  AND timestamp < datetime('now','-15 minutes'))
                    OR (file_path LIKE '%(output)%' AND timestamp < datetime('now','-7 days')))
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            let fm = FileManager.default
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let c = sqlite3_column_text(stmt, 0) else { continue }
                let p = String(cString: c)
                if fm.fileExists(atPath: p) { try? fm.removeItem(atPath: p) }
            }
        }
    }

    // MARK: - Transcript export

    // Builds a readable text of the most recent finished meeting and opens it.
    func exportLastTranscript() {
        engine.engineAPI("meetings?limit=5", method: "GET", body: nil) { [weak self] json in
            var rows = json as? [[String: Any]]
            if rows == nil, let obj = json as? [String: Any] {
                rows = obj["meetings"] as? [[String: Any]]
            }
            guard let meeting = rows?.first(where: { $0["meeting_end"] is String }) ?? rows?.first,
                  let id = meeting["id"] as? Int else { return }
            self?.engine.engineAPI("meetings/\(id)/transcript", method: "GET", body: nil) { t in
                var segs = t as? [[String: Any]]
                if segs == nil, let obj = t as? [String: Any] {
                    segs = (obj["segments"] ?? obj["transcript"]) as? [[String: Any]]
                }
                guard let segs, !segs.isEmpty else { return }
                var out = "litepipe — meeting transcript\n\n"
                for s in segs {
                    let text = (s["transcript"] ?? s["transcription"] ?? s["text"]) as? String ?? ""
                    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                    let device = ((s["device_type"] ?? s["deviceType"]) as? String ?? "").lowercased()
                    let speaker = (s["speaker_name"] ?? s["speakerName"]) as? String
                    let who = device.contains("input") ? "You" : (speaker ?? "Them")
                    out += "\(who): \(text)\n"
                }
                let url = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Desktop/litepipe-meeting-\(id).txt")
                try? out.write(to: url, atomically: true, encoding: .utf8)
                DispatchQueue.main.async { NSWorkspace.shared.open(url) }
            }
        }
    }
}
