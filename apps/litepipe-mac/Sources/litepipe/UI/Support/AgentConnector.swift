import Foundation

/// Points an assistant the person already uses at this archive.
///
/// Every one of these apps reads MCP servers out of a JSON file. Connecting is
/// therefore adding one entry to a file they own, which is a thing they could do
/// by hand and nobody should have to. Existing entries are left alone: this file
/// belongs to them and usually already has other servers in it.
enum AgentConnector {

    struct Target: Identifiable {
        let id: String
        let name: String
        let symbol: String
        /// Where the answer appears once connected.
        let answersHere: Bool
        /// What has to exist for this to be installed at all.
        let appPath: String
        /// The file the assistant reads its servers from.
        let configPath: String
        let download: String

        var isInstalled: Bool { FileManager.default.fileExists(atPath: appPath) }
        var isConnected: Bool { AgentConnector.isConnected(self) }
    }

    static var targets: [Target] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            Target(id: "claude-desktop", name: "Claude Desktop", symbol: "sparkles",
                   answersHere: false,
                   appPath: "/Applications/Claude.app",
                   configPath: "\(home)/Library/Application Support/Claude/claude_desktop_config.json",
                   download: "https://claude.ai/download"),
            Target(id: "claude-code", name: "Claude Code", symbol: "terminal",
                   answersHere: true,
                   appPath: "\(home)/.local/bin/claude",
                   configPath: "\(home)/.claude.json",
                   download: "https://claude.com/claude-code"),
            Target(id: "cursor", name: "Cursor", symbol: "curlybraces",
                   answersHere: false,
                   appPath: "/Applications/Cursor.app",
                   configPath: "\(home)/.cursor/mcp.json",
                   download: "https://cursor.com"),
        ]
    }

    static var installed: [Target] { targets.filter(\.isInstalled) }

    /// The same wiring the Connect button writes, as a line someone can run
    /// themselves. Registering it with the CLI rather than editing a file means
    /// it survives the CLI moving its config, which it has done before.
    static var claudeCodeCommand: String {
        "claude mcp add litepipe -- \(serverPath)"
    }

    // MARK: - Requirements

    /// The bridge is a second executable inside this bundle, next to the app's own.
    ///
    /// It used to be a Node script under ~/.litepipe, which meant Connect wrote a
    /// path that existed on one machine in the world. Reading it out of the bundle
    /// means it is there for anyone who dragged the app to Applications, it moves
    /// with the app, and it is covered by the same signature and notarisation.
    /// Whether the bridge being registered is the one inside the app, or the one a
    /// `swift build` left in a build directory.
    static var isBundled: Bool {
        FileManager.default.isExecutableFile(atPath: bundledServerPath)
    }

    private static var bundledServerPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/litepipe-mcp").path
    }

    static var serverPath: String {
        let bundled = bundledServerPath
        if FileManager.default.isExecutableFile(atPath: bundled) { return bundled }
        // A dev build has no bundle around it, so fall back to the sibling the
        // same `swift build` produced. Without this the connect flow can only be
        // tried by assembling an app first, which is the slowest way to find out
        // it is wrong.
        return Bundle.main.executableURL?.deletingLastPathComponent()
            .appendingPathComponent("litepipe-mcp").path ?? bundled
    }

    /// The bridge exists unless the app was assembled wrong, which is worth
    /// checking rather than assuming: a `swift run` from a checkout has no bundle.
    static var isReady: Bool {
        FileManager.default.isExecutableFile(atPath: serverPath)
    }

    // MARK: - Connect

    @discardableResult
    static func connect(_ target: Target) -> Bool {
        guard isReady else { return false }
        // No key and no port: the bridge opens the archive file directly, so it
        // answers with the app closed and there is no secret to leak into a
        // config file that other tools read.
        let entry: [String: Any] = ["command": serverPath, "args": [] as [String]]

        var root = readJSON(target.configPath) ?? [:]
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        servers["litepipe"] = entry
        root["mcpServers"] = servers
        return writeJSON(root, to: target.configPath)
    }

    static func disconnect(_ target: Target) {
        guard var root = readJSON(target.configPath),
              var servers = root["mcpServers"] as? [String: Any] else { return }
        servers.removeValue(forKey: "litepipe")
        root["mcpServers"] = servers
        _ = writeJSON(root, to: target.configPath)
    }

    /// Connected means wired to this app's bridge, not merely that something once
    /// claimed the name. An entry left by an older version points at a Node script
    /// that is no longer shipped, and reporting that as connected shows a green
    /// tick above a client that fails on every question.
    static func isConnected(_ target: Target) -> Bool {
        guard let root = readJSON(target.configPath),
              let servers = root["mcpServers"] as? [String: Any],
              let entry = servers["litepipe"] as? [String: Any],
              let command = entry["command"] as? String else { return false }
        return command == serverPath
    }

    // MARK: - Files

    private static func readJSON(_ path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func writeJSON(_ object: [String: Any], to path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        guard let data = try? JSONSerialization.data(withJSONObject: object,
                                                     options: [.prettyPrinted, .sortedKeys])
        else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
