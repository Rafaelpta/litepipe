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
        let key = UserDefaults.standard.string(forKey: "engine.apikey") ?? "$(litepipe key)"
        let node = nodePath ?? "node"
        return "claude mcp add litepipe -e LITEPIPE_API_KEY=\(key) -- \(node) \(serverPath)"
    }

    // MARK: - Requirements

    /// The MCP server is a Node script, so Node has to exist. GUI apps do not
    /// inherit a shell PATH, hence the hunt.
    static var nodePath: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node",
                "\(home)/.local/bin/node"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var serverPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".litepipe/mcp/src/index.js").path
    }

    static var isReady: Bool {
        nodePath != nil && FileManager.default.fileExists(atPath: serverPath)
    }

    // MARK: - Connect

    @discardableResult
    static func connect(_ target: Target) -> Bool {
        guard let node = nodePath else { return false }
        let key = UserDefaults.standard.string(forKey: "engine.apikey") ?? ""
        let entry: [String: Any] = [
            "command": node,
            "args": [serverPath],
            "env": ["LITEPIPE_API_KEY": key],
        ]

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

    static func isConnected(_ target: Target) -> Bool {
        guard let root = readJSON(target.configPath),
              let servers = root["mcpServers"] as? [String: Any] else { return false }
        return servers["litepipe"] != nil
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
