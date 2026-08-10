import Foundation

/// Asks the person's own agent about the archive, and shows the work while it
/// happens.
///
/// This shells out to the `claude` CLI rather than talking to an API, so nobody
/// has to paste a key and nothing is billed to litepipe. The archive reaches the
/// model through litepipe-mcp, the bridge shipped beside this app, which opens the
/// SQLite file directly.
///
/// Three things had to be right before a question could be answered from inside
/// this window, and each of them failed silently in a way that looked like a
/// broken chat rather than a misconfigured one:
///
/// * The config pointed at a Node script that only existed on one machine.
/// * Without `--strict-mcp-config` the CLI also loads whatever servers the person
///   registered themselves, so the model would reach for a tool outside the
///   allowed list.
/// * A tool that is not pre approved raises a permission prompt, and `-p` is not
///   interactive, so the run ended with the model politely explaining that it
///   could not proceed. The window printed that as if it were the answer.
enum AgentBridge {

    enum Failure: LocalizedError {
        case noCLI
        case noBridge
        case timedOut(Int)
        case cancelled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .noCLI:
                return "Claude Code is not installed on this Mac, so there is nothing here to answer with. Connect a desktop client instead and ask there."
            case .noBridge:
                return "The litepipe bridge is missing from this build, so an agent has no way to reach the archive."
            case .timedOut(let s):
                return "The agent went quiet for \(s) seconds and was stopped. Ask something narrower, or try again."
            case .cancelled:
                return "Stopped."
            case .failed(let why):
                return why
            }
        }
    }

    /// What the window shows while the answer is being built. Without this a
    /// question sits behind a spinner for twenty seconds with nothing to read.
    enum Update {
        case activity(String)
        case text(String)
    }

    struct Answer {
        let text: String
        /// Carried into the next question so a follow up keeps the thread.
        let sessionID: String?
    }

    /// GUI apps do not inherit a login shell's PATH, so the usual places are
    /// checked by hand rather than trusting `which`.
    static var cliPath: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude",
                "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var isAvailable: Bool { cliPath != nil }

    /// The tools the model may call, named for the server this app registers.
    /// These have to match the server key in the config below exactly: a mismatch
    /// does not fail loudly, it turns every tool call into a permission request
    /// that nobody can answer.
    private static let allowedTools = [
        "search_content", "activity_summary", "list_meetings",
        "meeting_transcript", "frame_context", "query",
    ].map { "mcp__litepipe__\($0)" }.joined(separator: ",")

    /// Seconds of silence before the run is considered hung. Long, because a real
    /// question runs several queries and the model thinks between them.
    private static let quietTimeout = 150

    /// The run in flight, so the window can stop it. One question at a time, which
    /// is what the pane allows.
    nonisolated(unsafe) private static var running: Process?

    /// Set by `cancel`, read after the process exits. Termination status is not
    /// enough: the CLI catches the signal and exits cleanly, having already
    /// printed a partial answer, so a stopped run is indistinguishable from a
    /// finished one unless the stop is recorded here.
    nonisolated(unsafe) private static var stopped = false

    static var isRunning: Bool { running?.isRunning ?? false }

    static func cancel() {
        stopped = true
        running?.terminate()
        running = nil
    }

    // MARK: - Ask

    static func ask(_ question: String,
                    resuming session: String? = nil,
                    onUpdate: @escaping @Sendable (Update) -> Void) async throws -> Answer {
        guard let cli = cliPath else { throw Failure.noCLI }
        guard AgentConnector.isReady else { throw Failure.noBridge }
        let config = try writeMCPConfig()

        let p = Process()
        p.executableURL = URL(fileURLWithPath: cli)
        var args = [
            "-p", question,
            "--mcp-config", config.path,
            // Only the archive. Without this the person's own registered servers
            // join the session and the model reaches for tools it may not use.
            "--strict-mcp-config",
            "--allowed-tools", allowedTools,
            "--output-format", "stream-json",
            "--verbose", // stream-json refuses to emit without it
        ]
        if let session, !session.isEmpty { args += ["--resume", session] }
        p.arguments = args

        // A window app inherits almost no PATH. The CLI is a native binary so it
        // does not strictly need one, but anything it shells out to does.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        p.environment = env

        p.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err

        running = p
        stopped = false
        defer { if running === p { running = nil } }

        let collector = Collector(onUpdate: onUpdate)

        try p.run()

        // Read stdout as it arrives rather than waiting for exit: the whole point
        // is that the window fills while the model works.
        let reader = Task.detached {
            var buffer = Data()
            let handle = out.fileHandleForReading
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let line = buffer.subdata(in: buffer.startIndex..<nl)
                    buffer.removeSubrange(buffer.startIndex...nl)
                    if !line.isEmpty { await collector.consume(line) }
                }
            }
            if !buffer.isEmpty { await collector.consume(buffer) }
        }

        // A watchdog rather than a deadline: a long answer is fine, a silent one
        // is not, so the clock resets every time something arrives.
        let watchdog = Task.detached {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if await collector.silentFor() > Double(quietTimeout), p.isRunning {
                    p.terminate()
                    return
                }
            }
        }

        await reader.value
        p.waitUntilExit()
        watchdog.cancel()

        let problem = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let result = await collector.result()

        if stopped { throw Failure.cancelled }
        if await collector.silentFor() > Double(quietTimeout) { throw Failure.timedOut(quietTimeout) }

        if let text = result.text, !text.isEmpty {
            return Answer(text: text, sessionID: result.session)
        }
        if let refusal = result.errorText, !refusal.isEmpty { throw Failure.failed(refusal) }
        throw Failure.failed(problem.isEmpty ? "The agent returned nothing." : problem)
    }

    // MARK: - Reading the stream

    /// Holds what the run has produced so far. An actor because the reader task,
    /// the watchdog and the caller all touch it.
    private actor Collector {
        private let onUpdate: @Sendable (Update) -> Void
        /// What the CLI declares as the answer at the end of the run.
        private var final = ""
        /// Everything the model said along the way, kept only in case the run ends
        /// without a result event to quote.
        private var streamed = ""
        private var session: String?
        private var errorText: String?
        private var last = Date()

        init(onUpdate: @escaping @Sendable (Update) -> Void) { self.onUpdate = onUpdate }

        func silentFor() -> Double { Date().timeIntervalSince(last) }

        func result() -> (text: String?, session: String?, errorText: String?) {
            let answer = final.isEmpty ? streamed : final
            return (answer.trimmingCharacters(in: .whitespacesAndNewlines), session, errorText)
        }

        /// Enough of the model's narration to read at a glance in the progress line.
        private static func firstSentence(_ s: String) -> String {
            let flat = s.replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            let cut = flat.prefix(90)
            guard let stop = cut.firstIndex(where: { ".!?".contains($0) }) else {
                return String(cut) + (flat.count > 90 ? "…" : "")
            }
            return String(flat[flat.startIndex...stop])
        }

        func consume(_ line: Data) {
            last = Date()
            guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
            switch event["type"] as? String {
            case "system":
                if let id = event["session_id"] as? String { session = id }
                if event["subtype"] as? String == "init" { onUpdate(.activity("Reading the archive")) }

            case "assistant":
                guard let message = event["message"] as? [String: Any],
                      let content = message["content"] as? [[String: Any]] else { return }
                for block in content {
                    switch block["type"] as? String {
                    case "text":
                        // Text between tool calls is the model narrating its way to
                        // an answer, not the answer. Appending it produced replies
                        // that began "I'll check your activity log." and ran into
                        // the real reply with no seam. It reads better as the
                        // progress line, which is where a person is already looking.
                        let t = block["text"] as? String ?? ""
                        guard !t.isEmpty else { break }
                        streamed += streamed.isEmpty ? t : "\n\n" + t
                        onUpdate(.text(t))
                        onUpdate(.activity(Self.firstSentence(t)))
                    case "tool_use":
                        // The CLI has housekeeping tools of its own. Narrating them
                        // says "Working" at a person who wanted to know what is
                        // being read, so only archive calls speak.
                        if let phrase = Self.phrase(for: block["name"] as? String ?? "") {
                            onUpdate(.activity(phrase))
                        }
                    default: break
                    }
                }

            case "result":
                if let id = event["session_id"] as? String { session = id }
                if let r = event["result"] as? String { final = r }
                if event["subtype"] as? String != "success", let r = event["result"] as? String {
                    errorText = r
                }

            default: break
            }
        }

        /// Tool names are for the model. This is for the person watching. Nil for
        /// anything that is not the archive being read.
        private static func phrase(for tool: String) -> String? {
            guard tool.hasPrefix("mcp__litepipe__") else { return nil }
            switch tool.replacingOccurrences(of: "mcp__litepipe__", with: "") {
            case "search_content": return "Searching what was on screen"
            case "activity_summary": return "Looking at how the day went"
            case "list_meetings": return "Checking the meetings"
            case "meeting_transcript": return "Reading a transcript"
            case "frame_context": return "Opening a moment"
            case "query": return "Querying the archive"
            default: return "Reading the archive"
            }
        }
    }

    // MARK: - Config

    /// Points at the bridge inside this app. It used to name a Node script under
    /// the home directory, which existed on exactly one machine in the world.
    private static func writeMCPConfig() throws -> URL {
        let config: [String: Any] = [
            "mcpServers": [
                "litepipe": ["command": AgentConnector.serverPath, "args": [] as [String]]
            ]
        ]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("litepipe-mcp.json")
        try JSONSerialization.data(withJSONObject: config).write(to: url)
        return url
    }
}
