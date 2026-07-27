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
    private var hotkeyMonitor: Any?
    private var chordActive = false
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
        guard pid == nil else { return }
        guard let bin = enginePath else { status = .error("engine not found"); return }
        intentionalStop = false
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        let envArr = env.map { "\($0.key)=\($0.value)" }
        // audio ON: the engine captures mic + transcribes (ASR/AI built into the binary)
        let args = [bin.path, "record", "--port", "\(port)", "--data-dir", dataDir.path]

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
        procSource?.cancel(); procSource = nil
        healthTimer?.invalidate(); healthTimer = nil
        if let p = pid { kill(p, SIGTERM) }
        pid = nil
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
                self.status = .starting
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.start() }
            }
        }
        src.resume()
        procSource = src
    }

    func togglePause() {
        switch status {
        case .recording, .starting: stop(markPaused: true); playCue(paused: true)
        case .paused, .stopped, .error: start(); playCue(paused: false)
        }
    }

    func openDataFolder() { NSWorkspace.shared.open(dataDir) }

    // MARK: - Global shortcut (option+control toggles context awareness)

    // A global .flagsChanged monitor toggles pause/resume when control+option are
    // pressed together (needs Accessibility, which litepipe already has). Debounced
    // so holding the chord fires once.
    private func startHotkey() {
        guard hotkeyMonitor == nil else { return }
        hotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] e in
            guard let self else { return }
            let both = e.modifierFlags.contains(.control) && e.modifierFlags.contains(.option)
            if both, !self.chordActive {
                self.chordActive = true
                DispatchQueue.main.async { self.togglePause() }
            } else if !both {
                self.chordActive = false
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
                }
            }
        }.resume()
    }
}
