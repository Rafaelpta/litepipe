import Foundation

/// Asks a real model about the archive, through the MCP server that already
/// speaks to the engine.
///
/// This is deliberately a bridge and not a client: it shells out to the `claude`
/// CLI, which is already installed and already signed in, so testing whether an
/// agent is useful over this data costs no API key and no account. The chat pane
/// keeps its offline answers as the default; this is opt in and says so.
///
/// It is also the one thing in the app that reaches the network, which is why it
/// is off unless asked for. The archive itself still never leaves: the model gets
/// only what a tool call returns, capped at twelve thousand characters.
enum AgentBridge {

    enum Failure: LocalizedError {
        case noCLI
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .noCLI:
                return "The claude command was not found. Install Claude Code, or turn this off to use the offline answers."
            case .failed(let why):
                return why
            }
        }
    }

    /// GUI apps do not inherit a login shell's PATH, so the usual places are
    /// checked by hand rather than trusting `which`.
    static var cliPath: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var isAvailable: Bool { cliPath != nil }

    /// The tools the model may call. Read only, all of them: this asks questions
    /// about the archive and can neither change it nor touch anything else.
    private static let allowedTools = [
        "mcp__litepipe__search-content",
        "mcp__litepipe__activity-summary",
        "mcp__litepipe__list-meetings",
        "mcp__litepipe__get-meeting-transcript",
        "mcp__litepipe__frame-context",
        "mcp__litepipe__search-elements",
        "mcp__litepipe__query",
    ].joined(separator: ",")

    static func ask(_ question: String) async throws -> String {
        guard let cli = cliPath else { throw Failure.noCLI }
        let config = try writeMCPConfig()

        let p = Process()
        p.executableURL = URL(fileURLWithPath: cli)
        p.arguments = [
            "-p", question,
            "--mcp-config", config.path,
            "--allowed-tools", allowedTools,
        ]
        // Without this the CLI waits three seconds for input that never comes.
        p.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err

        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let problem = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        let answer = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard p.terminationStatus == 0, !answer.isEmpty else {
            let why = String(decoding: problem, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.failed(why.isEmpty ? "The agent returned nothing." : why)
        }
        return answer
    }

    /// The engine refuses unauthenticated calls, and the key it prints from the
    /// CLI is not the one the app spawned it with. Read the app's own.
    private static func writeMCPConfig() throws -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let server = "\(home)/.litepipe/mcp/src/index.js"
        let key = UserDefaults.standard.string(forKey: "engine.apikey") ?? ""
        let config: [String: Any] = [
            "mcpServers": [
                "litepipe": [
                    "command": "node",
                    "args": [server],
                    "env": ["LITEPIPE_API_KEY": key],
                ]
            ]
        ]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("litepipe-mcp.json")
        try JSONSerialization.data(withJSONObject: config).write(to: url)
        return url
    }
}
