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

final class EngineController: ObservableObject {
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
    private var hotkeyMonitor: Any?
    private var chordActive = false
    private var chordDirty = false
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
            return
        }
        guard let bin = enginePath else { status = .error("engine not found"); return }
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
        let envArr = env.map { "\($0.key)=\($0.value)" }
        // audio ON by default (mic + system, transcribed); the Settings toggle can
        // disable it, persisted in UserDefaults.
        let audioOn = (UserDefaults.standard.object(forKey: "capture.audio") as? Bool) ?? true
        var args = [bin.path, "record", "--port", "\(port)", "--data-dir", dataDir.path]
        if !audioOn { args.append("--disable-audio") }

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
            watchProcess(newpid)
            startHealthPolling()
            startHotkey()
        } else {
            status = .error("spawn failed (\(rc))")
        }
    }

    func stop(markPaused: Bool = false) {
        intentionalStop = true
        restartWork?.cancel(); restartWork = nil
        procSource?.cancel(); procSource = nil
        healthTimer?.invalidate(); healthTimer = nil
        if let p = pid { kill(p, SIGTERM) }
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

    func togglePause() {
        switch status {
        case .recording, .starting:
            stop(markPaused: true); playCue(paused: true)
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

    // MARK: - Global shortcut (option+control toggles context awareness)

    // A global .flagsChanged monitor toggles pause/resume when control+option are
    // pressed together (needs Accessibility, which litepipe already has). Debounced
    // so holding the chord fires once.
    private func startHotkey() {
        guard hotkeyMonitor == nil else { return }
        // A quick TAP of the chord toggles on release. Any other key pressed
        // while it is down (window managers and app shortcuts use
        // control+option plus another key) marks the chord dirty and the
        // release does nothing — so those shortcuts no longer pause capture.
        hotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] e in
            guard let self else { return }
            if e.type == .keyDown {
                if self.chordActive { self.chordDirty = true }
                return
            }
            let both = e.modifierFlags.contains(.control) && e.modifierFlags.contains(.option)
            if both, !self.chordActive {
                self.chordActive = true
                self.chordDirty = false
            } else if !both, self.chordActive {
                self.chordActive = false
                if !self.chordDirty {
                    DispatchQueue.main.async { self.togglePause() }
                }
            }
        }
    }

    // Audible feedback on pause/resume, using litepipe's own bundled sounds
    // (original tones — not third-party assets). Falls back to a system sound.
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
                if s.contains("error") || s.contains("unhealthy") {
                    self.status = .error("engine unhealthy")
                } else if frame.contains("ok") || s.contains("healthy") || s.contains("ok") {
                    if self.status != .paused { self.status = .recording }
                    self.restartAttempts = 0 // healthy run resets the respawn budget
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

    // The engine's meeting detector publishes `in_meeting` on /health; the mic's
    // purpose is transcribing meetings, so input devices are paused outside them
    // (no permanent orange indicator) and resumed when a meeting is detected.
    // Screen and system-audio capture are untouched. Outside meetings the check
    // runs every poll because the engine's device monitor auto-starts a new
    // default input (e.g. after plugging a headset).
    private func syncMicGate(inMeeting: Bool) {
        let audioOn = (UserDefaults.standard.object(forKey: "capture.audio") as? Bool) ?? true
        guard audioOn, !micGateBusy else { return }
        if inMeeting, micGateInMeeting == true { return }
        micGateBusy = true
        engineAPI("audio/device/status", method: "GET", body: nil) { [weak self] json in
            guard let self else { return }
            var devices = json as? [[String: Any]]
            if devices == nil, let obj = json as? [String: Any] {
                devices = obj["devices"] as? [[String: Any]]
            }
            guard let devices else { self.micGateBusy = false; return }
            let toChange = devices.filter {
                guard ($0["name"] as? String ?? "").hasSuffix("(input)") else { return false }
                if inMeeting {
                    // Re-enable only what the gate itself paused; leave non-default
                    // inputs (virtual mics etc.) alone.
                    return ($0["is_user_disabled"] as? Bool) ?? false
                }
                return ($0["is_running"] as? Bool) ?? false
            }
            guard !toChange.isEmpty else {
                self.micGateInMeeting = inMeeting
                self.micGateBusy = false
                return
            }
            let action = inMeeting ? "audio/device/start" : "audio/device/stop"
            let group = DispatchGroup()
            for d in toChange {
                guard let name = d["name"] as? String else { continue }
                group.enter()
                self.engineAPI(action, method: "POST", body: ["device_name": name]) { _ in group.leave() }
            }
            group.notify(queue: .main) {
                self.micGateInMeeting = inMeeting
                self.micGateBusy = false
            }
        }
    }

    private func engineAPI(_ path: String, method: String, body: [String: Any]?,
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
