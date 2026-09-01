import AppKit
import Combine
import Darwin
import Foundation

// Drives the litepipe capture engine (the `screenpipe` core binary): spawns it as a
// child process, polls its local HTTP health endpoint, and exposes recording status
// + simple controls to the UI. Vision-only (audio disabled) for the lean build.
//
// The engine is spawned via posix_spawn with responsibility DISCLAIM=0 so litepipe
// stays the TCC "responsible process": the child then captures under litepipe's own
// Screen Recording / Accessibility grants instead of needing its own.
enum EngineStatus: Equatable {
    case stopped, starting, recording, paused
    case error(String)
}

// Append-only flight recorder (~/.litepipe/app.log): every engine start, stop,
// exit status and gate action lands here so a dead engine explains itself.
func litepipeLog(_ message: String) {
    let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".litepipe", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("app.log")
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let line = "\(fmt.string(from: Date())) \(message)\n"
    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile()
        h.write(line.data(using: .utf8)!)
        try? h.close()
    } else {
        try? line.write(to: url, atomically: true, encoding: .utf8)
    }
}

final class EngineController: ObservableObject {
    /// One engine for the whole app. The delegate owns its lifecycle and the
    /// scenes read its state; two controllers would race for the port, the data
    /// directory and the log.
    static let shared = EngineController()

    @Published private(set) var status: EngineStatus = .stopped

    private var pid: pid_t?
    private var healthTimer: Timer?
    private var procSource: DispatchSourceProcess?
    private var intentionalStop = false
    private var restartAttempts = 0
    private var restartWork: DispatchWorkItem?
    private let maxRestartAttempts = 5
    private var micGateBusy = false
    private var micGateInMeeting: Bool?

    // Local API key for the engine's control endpoints (write ops need auth).
    // Generated once, persisted, and handed to the engine via env at spawn.
    private lazy var apiKey: String = {
        if let k = UserDefaults.standard.string(forKey: "engine.apikey") { return k }
        let k = UUID().uuidString + UUID().uuidString
        UserDefaults.standard.set(k, forKey: "engine.apikey")
        return k
    }()
    // During a meeting the hotkey (and pause button) end the meeting cleanly
    // instead of killing the capture engine. Returns true when a meeting was
    // active and consumed the action. Set by the companion; if the tap was
    // accidental the banner re-suggests within seconds (windows still present).
    var meetingAbort: (() -> Bool)?
    private let port = 3030
    // litepipe's own data dir (avoids colliding with a screenpipe install).
    private let dataDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".litepipe", isDirectory: true)

    private var enginePath: URL? {
        if let u = Bundle.main.url(forResource: "screenpipe", withExtension: nil) { return u }
        let dev = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("projects/litepipe/target/release/screenpipe")
        return FileManager.default.isExecutableFile(atPath: dev.path) ? dev : nil
    }

    var dataFolder: URL { dataDir }

    // MARK: - Lifecycle

    func start() {
        restartWork?.cancel(); restartWork = nil
        guard pid == nil else { return }
        // The engine binary asks macOS for Screen Recording on every launch; spawning
        // it without the grant means a system dialog per spawn. Refuse instead.
        guard Permissions.isGranted(.screen) else {
            status = .error("screen recording permission required")
            litepipeLog("start refused: screen permission missing")
            return
        }
        guard let bin = enginePath else {
            status = .error("engine not found")
            litepipeLog("start refused: engine binary not found")
            return
        }
        intentionalStop = false
        micGateInMeeting = nil // re-apply the mic gate on the fresh engine
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

        // Prefer the bundled, self-contained ffmpeg/ffprobe (so capture works on
        // machines without Homebrew); fall back to Homebrew/system in dev.
        var env = ProcessInfo.processInfo.environment
        var pathParts: [String] = []
        if let bin = Bundle.main.resourceURL?.appendingPathComponent("bin", isDirectory: true).path {
            pathParts.append(bin)
        }
        pathParts += ["/opt/homebrew/bin", "/usr/local/bin", env["PATH"] ?? "/usr/bin:/bin"]
        env["PATH"] = pathParts.joined(separator: ":")
        env["SCREENPIPE_API_KEY"] = apiKey // lets the app drive the control endpoints
        // The engine inherits an update check that hits registry.npmjs.org at
        // startup and every few minutes. It is not covered by --disable-telemetry,
        // and litepipe promises loopback only, so both nudges are opted out here.
        env["SCREENPIPE_NO_UPDATE_CHECK"] = "1"
        env["SCREENPIPE_NO_REMINDERS"] = "1"
        // Beta diagnosability: the meeting detector only tells its story at debug level.
        env["SCREENPIPE_LOG"] = "screenpipe_engine::meeting_detector=debug"
        let envArr = env.map { "\($0.key)=\($0.value)" }
        // audio ON by default (mic + system, transcribed); the Settings toggle can
        // disable it, persisted in UserDefaults.
        let audioOn = (UserDefaults.standard.object(forKey: "capture.audio") as? Bool) ?? true
        // The engine's hardware-tier default picks whisper-tiny on 16GB Macs;
        // meeting transcription needs the large turbo model (downloads ~870MB on
        // first use; transcription is silent until the download finishes).
        let sttEngine = UserDefaults.standard.string(forKey: "transcription.engine")
            ?? "whisper-large-v3-turbo-quantized"
        // VoiceProcessingIO on the mic: automatic gain + echo cancellation (what
        // Zoom/Meet use). Without it the MacBook mic records so quietly that the
        // engine's silence gates discard real speech before transcription.
        // The engine inherits upstream PostHog and Sentry clients that are ON
        // unless this flag is passed; litepipe promises loopback only.
        var args = [bin.path, "record", "--port", "\(port)", "--data-dir", dataDir.path,
                    "-a", sttEngine, "--macos-input-vpio-enabled", "--disable-telemetry"]
        if !audioOn { args.append("--disable-audio") }
        // Secret redaction (Settings > Privacy, on by default): background workers
        // rewrite keys/cards/passwords as labels in text and paint them black in
        // frames, overwriting the source. Backend stays "local" (the default) —
        // never the hosted enclave. Without the AI model the text worker degrades
        // to the 46 deterministic patterns; the image model self-downloads (54MB).
        if (UserDefaults.standard.object(forKey: "privacy.redactSecrets") as? Bool) ?? true {
            args += ["--async-pii-redaction", "--async-image-pii-redaction"]
        }
        // User exclusion lists (Settings > Privacy): comma or newline separated.
        func privacyList(_ key: String) -> [String] {
            (UserDefaults.standard.string(forKey: key) ?? "")
                .split(whereSeparator: { $0 == "," || $0.isNewline })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        for domain in privacyList("privacy.ignoredUrls") { args += ["--ignored-urls", domain] }
        for app in privacyList("privacy.ignoredApps") { args += ["--ignored-windows", app] }
        // Private-window belt and suspenders. The engine's own incognito
        // detector misses real Chrome windows (its AppleScript pass compares
        // titles by exact match and, on mismatch, never reaches the localized
        // title fallback — engine fix queued for the next engine build). The
        // ignore list has no such gap and excludes the window from the
        // ScreenCaptureKit buffer itself, so pin the private-window title
        // suffixes here. "::title" matches any app whose window title
        // contains it. Safari marks private windows with no title suffix, so
        // it stays covered only by the engine detector.
        for marker in ["(Incognito)", "(InPrivate)", "(Navigation privée)",
                       "(Navegação anônima)", "Private Browsing",
                       "Navegação privativa", "Navegação Privada"] {
            args += ["--ignored-windows", "::\(marker)"]
        }

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        setParentResponsible(&attr) // litepipe remains the TCC-responsible process

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        let logPath = dataDir.appendingPathComponent("engine-app.log").path
        let fd = open(logPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        if fd >= 0 {
            posix_spawn_file_actions_adddup2(&actions, fd, 1)
            posix_spawn_file_actions_adddup2(&actions, fd, 2)
        }

        var newpid: pid_t = 0
        let rc = withCStringArray(args) { argv in
            withCStringArray(envArr) { envp in
                posix_spawn(&newpid, bin.path, &actions, &attr, argv, envp)
            }
        }
        if fd >= 0 { close(fd) }
        posix_spawn_file_actions_destroy(&actions)
        posix_spawnattr_destroy(&attr)

        if rc == 0 {
            pid = newpid
            status = .starting
            litepipeLog("engine spawned pid=\(newpid) attempt=\(restartAttempts)")
            watchProcess(newpid)
            startHealthPolling()
            startHotkey()
        } else {
            status = .error("spawn failed (\(rc))")
            litepipeLog("spawn failed rc=\(rc)")
        }
    }

    func stop(markPaused: Bool = false, source: String = "app") {
        intentionalStop = true
        restartWork?.cancel(); restartWork = nil
        procSource?.cancel(); procSource = nil
        healthTimer?.invalidate(); healthTimer = nil
        if let p = pid {
            kill(p, SIGTERM)
            litepipeLog("engine stopped pid=\(p) paused=\(markPaused) source=\(source)")
        }
        pid = nil
        micGateInMeeting = nil
        status = markPaused ? .paused : .stopped
    }

    // Detect an unexpected engine exit (crash) and auto-restart, unless we stopped
    // it on purpose (pause/quit).
    private func watchProcess(_ p: pid_t) {
        procSource?.cancel()
        let src = DispatchSource.makeProcessSource(identifier: p, eventMask: .exit, queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            self.procSource?.cancel(); self.procSource = nil
            self.pid = nil
            self.healthTimer?.invalidate(); self.healthTimer = nil
            var st: Int32 = 0
            waitpid(p, &st, WNOHANG) // reap; expose why it died
            let sig = st & 0x7f
            let code = (st >> 8) & 0xff
            litepipeLog("engine exited pid=\(p) code=\(code) signal=\(sig) intentional=\(self.intentionalStop)")
            if !self.intentionalStop {
                guard Permissions.isGranted(.screen) else {
                    self.status = .error("screen recording permission missing")
                    return
                }
                self.restartAttempts += 1
                guard self.restartAttempts <= self.maxRestartAttempts else {
                    self.status = .error("engine keeps exiting")
                    return
                }
                self.status = .starting
                let delay = min(pow(2.0, Double(self.restartAttempts - 1)), 30)
                let work = DispatchWorkItem { [weak self] in self?.start() }
                self.restartWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            }
        }
        src.resume()
        procSource = src
    }

    func togglePause(source: String = "ui") {
        litepipeLog("togglePause source=\(source) status=\(status)")
        switch status {
        case .recording, .starting:
            stop(markPaused: true, source: source); playCue(paused: true)
        case .paused, .stopped, .error:
            start()
            if case .error = status { return } // start refused (no permission): no cue
            playCue(paused: false)
        }
    }

    func openDataFolder() { NSWorkspace.shared.open(dataDir) }

    // Stop and start again (e.g. after changing the audio setting).
    func restart() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.start() }
    }

    // MARK: - Global shortcut

    // The shortcut itself lives in GlobalHotkey, which matches a key the user
    // chose rather than watching for a bare chord on the way up.
    private func startHotkey() {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                GlobalHotkey.shared.start { [weak self] in
                    guard let self else { return }
                    if self.meetingAbort?() == true {
                        litepipeLog("hotkey ended the meeting transcription")
                        self.playCue(paused: true)
                        return
                    }
                    self.togglePause(source: "hotkey")
                }
            }
        }
    }

    // Audible feedback on pause/resume, using litepipe's own bundled sounds
    // (original tones — not third-party assets). Falls back to a system sound.
    /// The one piece of feedback capture gives: a tone on the way down and a
    /// tone on the way up. The window drives the engine directly rather than
    /// through `togglePause`, so it asks for the cue itself.
    func cue(paused: Bool) { playCue(paused: paused) }

    private func playCue(paused: Bool) {
        let name = paused ? "stop" : "play"
        if let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "sounds"),
           let sound = NSSound(contentsOf: url, byReference: true) {
            sound.play()
        } else {
            NSSound(named: NSSound.Name(paused ? "Tink" : "Pop"))?.play()
        }
    }

    // MARK: - Responsibility (TCC inheritance)

    private func setParentResponsible(_ attr: UnsafeMutablePointer<posix_spawnattr_t?>) {
        guard let handle = dlopen(nil, RTLD_NOW),
              let sym = dlsym(handle, "responsibility_spawnattrs_setdisclaim") else { return }
        typealias Fn = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>?, Int32) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        _ = fn(attr, 0) // 0 = do NOT disclaim -> parent app is responsible
    }

    private func withCStringArray<R>(_ strings: [String],
                                     _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> R) -> R {
        var cs: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) }
        cs.append(nil)
        defer { for p in cs where p != nil { free(p) } }
        return cs.withUnsafeMutableBufferPointer { body($0.baseAddress!) }
    }

    // MARK: - Health polling

    private func startHealthPolling() {
        healthTimer?.invalidate()
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.pollHealth() }
        RunLoop.main.add(t, forMode: .common)
        healthTimer = t
        pollHealth()
    }

    private func pollHealth() {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, _ in
            DispatchQueue.main.async {
                guard let self, self.pid != nil else { return }
                guard let http = resp as? HTTPURLResponse, http.statusCode == 200, let data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return } // engine still coming up -> stay `.starting`
                let s = (obj["status"] as? String ?? "").lowercased()
                let frame = (obj["frame_status"] as? String ?? "").lowercased()
                // Frame health leads: with audio intentionally stopped outside
                // meetings, the overall status may read degraded — that's not
                // an engine failure.
                if frame.contains("ok") || s.contains("healthy") || s.contains("ok") {
                    if self.status != .paused { self.status = .recording }
                    self.restartAttempts = 0 // healthy run resets the respawn budget
                } else if s.contains("error") || s.contains("unhealthy") {
                    if self.micGateInMeeting != false { self.status = .error("engine unhealthy") }
                }
                // This engine build only reports meeting state on /meetings/status.
                self.engineAPI("meetings/status", method: "GET", body: nil) { json in
                    let active = ((json as? [String: Any])?["active"] as? Bool) ?? false
                    self.syncMicGate(inMeeting: active)
                }
            }
        }.resume()
    }

    // MARK: - Microphone gate (mic records only during meetings)

    // The mic exists to transcribe meetings. Outside them the whole audio
    // pipeline is STOPPED (not paused): the engine's per-device pause keeps the
    // microphone claimed and macOS shows the orange indicator permanently, which
    // reads as "always listening". A full stop releases the device — indicator
    // off. Cost: system audio isn't transcribed outside meetings either; screen
    // capture (frames/OCR) is unaffected.
    private func syncMicGate(inMeeting: Bool) {
        let audioOn = (UserDefaults.standard.object(forKey: "capture.audio") as? Bool) ?? true
        guard audioOn, !micGateBusy else { return }
        if micGateInMeeting == inMeeting { return }
        micGateBusy = true
        let action = inMeeting ? "audio/start" : "audio/stop"
        engineAPI(action, method: "POST", body: [:]) { [weak self] json in
            guard let self else { return }
            if json != nil {
                litepipeLog("audio gate: \(inMeeting ? "started (meeting)" : "stopped, devices released (idle)")")
                self.micGateInMeeting = inMeeting
            }
            self.micGateBusy = false
        }
    }

    func engineAPI(_ path: String, method: String, body: [String: Any]?,
                   done: @escaping (Any?) -> Void) {
        guard let url = URL(string: "http://127.0.0.1:\(port)/\(path)") else { done(nil); return }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 2
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        URLSession.shared.dataTask(with: req) { data, _, _ in
            DispatchQueue.main.async {
                done(data.flatMap { try? JSONSerialization.jsonObject(with: $0) })
            }
        }.resume()
    }
}
