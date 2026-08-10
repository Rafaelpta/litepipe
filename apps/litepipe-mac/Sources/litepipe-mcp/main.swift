import Foundation

/// litepipe-mcp: hands the archive to whatever agent the person already pays for.
///
/// This ships inside litepipe.app as a second executable, so connecting a model
/// costs no download, no runtime and no install step: the client spawns this
/// binary and talks to it over stdin and stdout. The alternative it replaces was
/// a Node script that reached a machine only by being copied there by hand.
///
/// It reads the same SQLite file the window reads, through the same reader, on
/// purpose. An agent that answers "what did I do yesterday" differently from the
/// timeline sitting next to it is worse than one that cannot answer at all.
///
/// Nothing here writes. Nothing here opens a socket. The only bytes that leave
/// this machine are the ones the agent quotes back to whoever asked.

// stdout carries protocol messages and nothing else: a stray print corrupts the
// stream and the client drops the connection with no useful error. Diagnostics
// go to stderr, which clients show in their logs.
func note(_ s: String) {
    FileHandle.standardError.write(("litepipe-mcp: " + s + "\n").data(using: .utf8)!)
}

/// The MCP stdio transport is newline delimited JSON-RPC. One message per line,
/// no length headers.
func send(_ message: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: message, options: [.withoutEscapingSlashes]) else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}

func reply(_ id: Any, _ result: [String: Any]) {
    send(["jsonrpc": "2.0", "id": id, "result": result])
}

func fail(_ id: Any, _ code: Int, _ message: String) {
    send(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
}

/// A tool result is content blocks; errors come back as content with isError so
/// the model can read what went wrong and try a different call, rather than the
/// client tearing down the session over a bad argument.
func toolResult(_ id: Any, text: String, isError: Bool = false) {
    reply(id, ["content": [["type": "text", "text": text]], "isError": isError])
}

// MARK: - Loop

note("started, archive at \(ContextDB.defaultPath)")

while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty,
          let data = line.data(using: .utf8),
          let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { continue }

    let method = msg["method"] as? String ?? ""
    let id = msg["id"]

    switch method {
    case "initialize":
        // Echo the version the client asked for. Pinning our own would make a
        // newer client fail on a field neither side actually disagrees about.
        let params = msg["params"] as? [String: Any] ?? [:]
        let version = params["protocolVersion"] as? String ?? "2025-06-18"
        reply(id as Any, [
            "protocolVersion": version,
            "capabilities": ["tools": [:] as [String: Any]],
            "serverInfo": ["name": "litepipe", "version": "0.3.0"],
            "instructions": """
                litepipe is a local archive of everything this Mac has shown, said or heard: \
                screen text captured as it changed, plus meeting transcripts. It is read only.

                Prefer search_content to find moments and query for anything that needs \
                counting, grouping or a time window. Timestamps are UTC in ISO 8601; use \
                datetime(timestamp) to compare them.
                """,
        ])

    case "notifications/initialized", "notifications/cancelled":
        break // no response is expected for a notification

    case "ping":
        reply(id as Any, [:])

    case "tools/list":
        reply(id as Any, ["tools": Tools.manifest])

    case "tools/call":
        let params = msg["params"] as? [String: Any] ?? [:]
        let name = params["name"] as? String ?? ""
        let args = params["arguments"] as? [String: Any] ?? [:]
        guard let tool = Tools.byName[name] else {
            toolResult(id as Any, text: "No tool named \(name).", isError: true)
            break
        }
        do {
            toolResult(id as Any, text: try tool.run(args))
        } catch {
            toolResult(id as Any, text: error.localizedDescription, isError: true)
        }

    default:
        // Notifications carry no id and want no answer; requests do.
        if let id { fail(id, -32601, "Unknown method \(method)") }
    }
}

note("stdin closed, exiting")
