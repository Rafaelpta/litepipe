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
        /// Whether the client has to be restarted before it notices the new
        /// server. A long running process reads its config once at launch; one
        /// that is spawned per question picks the wiring up on the next one.
        let needsRestart: Bool
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
                   needsRestart: true,
                   appPath: "/Applications/Claude.app",
                   configPath: "\(home)/Library/Application Support/Claude/claude_desktop_config.json",
                   download: "https://claude.ai/download"),
            Target(id: "claude-code", name: "Claude Code", symbol: "terminal",
                   needsRestart: false,
                   appPath: "\(home)/.local/bin/claude",
                   configPath: "\(home)/.claude.json",
                   download: "https://claude.com/claude-code"),
            Target(id: "cursor", name: "Cursor", symbol: "curlybraces",
                   needsRestart: true,
                   appPath: "/Applications/Cursor.app",
                   configPath: "\(home)/.cursor/mcp.json",
                   download: "https://cursor.com"),
        ]
    }

    static var installed: [Target] { targets.filter(\.isInstalled) }

    /// The same wiring the Connect button writes, as something someone can run or
    /// paste themselves. Registering through a CLI rather than editing a file means
    /// it survives that CLI moving its config, which both of them have done before.
    ///
    /// Three of them because the button only covers clients whose config is JSON
    /// under `mcpServers`. Codex keeps TOML in `~/.codex/config.toml`, so it cannot
    /// be written by the same code, and a page that only spoke Claude left everyone
    /// else reading a list their agent was not on.
    enum Recipe: String, CaseIterable, Identifiable {
        case claudeCode = "Claude Code"
        case codex = "Codex"
        case json = "JSON"

        var id: String { rawValue }

        /// What the snippet is for, in the one line under it.
        var note: String {
            switch self {
            case .claudeCode: "Run it in a terminal."
            case .codex: "Run it in a terminal. Covers the Codex CLI, the ChatGPT app and the IDE extension, which share one config."
            case .json: "For any other MCP client. Add it to that client's config, next to whatever is already there."
            }
        }
    }

    static func recipe(_ kind: Recipe) -> String {
        switch kind {
        case .claudeCode:
            // `--scope user` or the server is registered for the current directory
            // only, and every session started anywhere else answers as though the
            // archive does not exist. A memory is not a per project tool. The
            // Connect button already writes at user scope; this line did not.
            return "claude mcp add --scope user litepipe -- \(serverPath)"
        case .codex:
            return "codex mcp add litepipe -- \(serverPath)"
        case .json:
            return """
                   "litepipe": {
                     "command": "\(serverPath)",
                     "args": []
                   }
                   """
        }
    }

    static var claudeCodeCommand: String { recipe(.claudeCode) }

    // MARK: - Requirements

    /// The bridge is a second executable inside this bundle, next to the app's own.
    ///
    /// It used to be a Node script under ~/.litepipe, which meant Connect wrote a
    /// path that existed on one machine in the world. Reading it out of the bundle
    /// means it is there for anyone who dragged the app to Applications, it moves
    /// with the app, and it is covered by the same signature and notarisation.
    static var isBundled: Bool {
        FileManager.default.isExecutableFile(atPath: bundledServerPath)
    }

    /// Where the app happens to be running from, which decides whether connecting
    /// is safe at all.
    ///
    /// A client config holds an absolute path and reads it back weeks later. Written
    /// while the app runs from a mounted disk image it names `/Volumes/litepipe/…`,
    /// which stops existing the moment the image is ejected. The person is then left
    /// with a server that fails every question and nothing on screen explaining why.
    /// macOS adds a second version of the same trap: a freshly downloaded app is run
    /// from a read only translocated copy whose path is a random directory that is
    /// gone by the next launch.
    enum Location {
        /// A stable path. Writing it into a config is safe.
        case installed
        /// Running from a mounted image, so the path dies on eject.
        case removableVolume
        /// Running from App Translocation, so the path dies on quit.
        case translocated
        /// No bundle at all, which is a `swift build` from a checkout.
        case development
    }

    static var location: Location {
        guard isBundled else { return .development }
        let path = Bundle.main.bundleURL.path
        if path.hasPrefix("/Volumes/") { return .removableVolume }
        if path.contains("/AppTranslocation/") { return .translocated }
        return .installed
    }

    private static var bundledServerPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/litepipe-mcp").path
    }

    /// The copy sitting at a path that survives this app being quit or unmounted.
    private static var installedServerPath: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for app in ["/Applications/litepipe.app", "\(home)/Applications/litepipe.app"] {
            let candidate = app + "/Contents/MacOS/litepipe-mcp"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// The path that gets written into somebody else's config file.
    ///
    /// The running copy is preferred while it lives somewhere stable, so a developer
    /// testing a build registers the build they are testing. Only when the running
    /// copy is somewhere that will disappear does it fall back to an installed one.
    static var serverPath: String {
        switch location {
        case .installed:
            return bundledServerPath
        case .removableVolume, .translocated:
            return installedServerPath ?? bundledServerPath
        case .development:
            // A dev build has no bundle around it, so fall back to the sibling the
            // same `swift build` produced. Without this the connect flow can only be
            // tried by assembling an app first, which is the slowest way to find out
            // it is wrong.
            return Bundle.main.executableURL?.deletingLastPathComponent()
                .appendingPathComponent("litepipe-mcp").path ?? bundledServerPath
        }
    }

    /// The bridge exists unless the app was assembled wrong, which is worth
    /// checking rather than assuming: a `swift run` from a checkout has no bundle.
    static var isReady: Bool {
        FileManager.default.isExecutableFile(atPath: serverPath)
    }

    /// Whether a path written now will still resolve after this app is quit.
    static var canConnect: Bool {
        guard isReady else { return false }
        switch location {
        case .installed, .development: return true
        case .removableVolume, .translocated: return installedServerPath != nil
        }
    }

    /// What to say instead of connecting, in words the person can act on.
    static var blockedReason: String? {
        if !isReady {
            return "The bridge is missing from this copy of litepipe. Download the app again."
        }
        guard !canConnect else { return nil }
        switch location {
        case .removableVolume:
            return "litepipe is running from the disk image. Drag it to Applications and open it "
                 + "from there, otherwise the connection breaks as soon as the image is ejected."
        case .translocated:
            return "macOS is running litepipe from a temporary copy. Drag it to Applications and "
                 + "open it from there, otherwise the connection breaks when the app quits."
        case .installed, .development:
            return nil
        }
    }

    // MARK: - Connect

    @discardableResult
    static func connect(_ target: Target) -> Bool {
        guard canConnect else { return false }
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
