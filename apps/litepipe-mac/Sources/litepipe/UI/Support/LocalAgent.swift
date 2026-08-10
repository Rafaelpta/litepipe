import Foundation

/// A model running on this Mac, answering questions about the archive.
///
/// The offline answers this replaces are assembled from templates: correct, and
/// obviously assembled. A model writes properly. The point of running it here is
/// that the archive is the most private thing on the machine, and the moment an
/// answer requires sending it somewhere the product's whole claim is up for
/// negotiation.
///
/// Ollama is the host: it is one download, it serves on 127.0.0.1, and it speaks
/// tools. litepipe never bundles a model, so nobody pays for a five gigabyte app
/// they did not ask for.
enum LocalAgent {
    static let base = "http://127.0.0.1:11434"

    /// Models small enough for a laptop that can still call tools. First one
    /// installed wins; the list is preference order, not a requirement.
    static let preferred = ["qwen2.5:7b", "llama3.1:8b", "qwen2.5:3b", "llama3.2:3b"]

    struct Unavailable: LocalizedError {
        let reason: String
        var errorDescription: String? { reason }
    }

    // MARK: - Is it there

    static func installedModels() async -> [String] {
        guard let url = URL(string: base + "/api/tags") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["name"] as? String }
    }

    /// The model to use, or nil when Ollama is missing or holds nothing useful.
    static func chosenModel(from installed: [String]) -> String? {
        for want in preferred {
            if let hit = installed.first(where: { $0 == want || $0.hasPrefix(want + "-") }) {
                return hit
            }
        }
        // Anything is better than nothing: tool support varies, and a model that
        // cannot call tools still answers from what the first search returns.
        return installed.first
    }

    // MARK: - The loop

    /// Ask, let the model call tools, feed the results back, repeat until it
    /// answers. Capped: a model that keeps calling tools is stuck, and the person
    /// is watching a spinner.
    static func ask(_ question: String, model: String,
                    tools: ArchiveTools, maxRounds: Int = 6) async throws -> String {
        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": question],
        ]

        for _ in 0..<maxRounds {
            let reply = try await chat(messages: messages, model: model)
            let message = reply["message"] as? [String: Any] ?? [:]
            let calls = message["tool_calls"] as? [[String: Any]] ?? []

            if calls.isEmpty {
                let text = (message["content"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { throw Unavailable(reason: "The model answered with nothing.") }
                return text
            }

            messages.append(message)
            for call in calls {
                let fn = call["function"] as? [String: Any] ?? [:]
                let name = fn["name"] as? String ?? ""
                let args = fn["arguments"] as? [String: Any] ?? [:]
                let result = await tools.run(name, args)
                messages.append(["role": "tool", "content": result])
            }
        }
        throw Unavailable(reason: "The model kept looking and never answered. Try a shorter question.")
    }

    private static let systemPrompt = """
    You answer questions about a person's own archive of what was on their screen \
    and what was said around them, captured on this Mac. Use the tools to look \
    things up rather than guessing; if the tools return nothing, say so plainly \
    instead of inventing an answer. Be brief and concrete: name apps, windows and \
    times. Never claim anything the tools did not return.
    """

    private static func chat(messages: [[String: Any]], model: String) async throws -> [String: Any] {
        guard let url = URL(string: base + "/api/chat") else {
            throw Unavailable(reason: "Bad Ollama address.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": messages,
            "tools": ArchiveTools.schema,
            "stream": false,
        ])
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Unavailable(reason: "Ollama returned something unreadable.")
        }
        if let error = json["error"] as? String { throw Unavailable(reason: error) }
        return json
    }
}

/// What the model is allowed to look up. These read the archive that is already
/// loaded in the app, so there is no server, no MCP and no second copy of the
/// data: the tools are the same functions the rest of the window uses.
@MainActor
final class ArchiveTools {
    private let library: ContextLibrary
    init(library: ContextLibrary) { self.library = library }

    static let schema: [[String: Any]] = [
        tool("search_archive",
             "Find captures whose text, app, window or site matches a query.",
             ["query": ["type": "string", "description": "What to look for"]],
             ["query"]),
        tool("summarise_day",
             "What happened on a day: the apps, how long in each, and the busiest windows.",
             ["date": ["type": "string", "description": "YYYY-MM-DD, or omit for the most recent day"]],
             []),
        tool("list_meetings",
             "Meetings that were detected, with title, time and whether a transcript exists.",
             [:], []),
        tool("meeting_transcript",
             "What was said in one meeting.",
             ["title": ["type": "string", "description": "Part of the meeting title"]],
             ["title"]),
    ]

    private static func tool(_ name: String, _ description: String,
                             _ properties: [String: Any], _ required: [String]) -> [String: Any] {
        ["type": "function",
         "function": ["name": name,
                      "description": description,
                      "parameters": ["type": "object",
                                     "properties": properties,
                                     "required": required]]]
    }

    /// Answers are text, not JSON: a small model reads prose more reliably than
    /// it reads a nested object, and this is what lands back in its context.
    func run(_ name: String, _ args: [String: Any]) async -> String {
        switch name {
        case "search_archive":
            return search(args["query"] as? String ?? "")
        case "summarise_day":
            return day(args["date"] as? String)
        case "list_meetings":
            return meetings()
        case "meeting_transcript":
            return transcript(args["title"] as? String ?? "")
        default:
            return "No such tool."
        }
    }

    private func search(_ query: String) -> String {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return "Empty query." }
        let hits = library.items.filter { p in
            p.excerpt.lowercased().contains(q) || p.window.lowercased().contains(q)
                || p.app.lowercased().contains(q) || (p.host?.lowercased().contains(q) ?? false)
        }
        guard !hits.isEmpty else { return "Nothing in the archive matches \"\(query)\"." }
        var out = "\(hits.count) moments match \"\(query)\". The most recent:\n"
        for p in hits.suffix(8).reversed() {
            out += "- \(stamp(p.date)) · \(p.app) · \(Photo.shortTitle(p.window, app: p.app, host: p.host))\n"
            let excerpt = p.excerpt.replacingOccurrences(of: "\n", with: " ")
            if !excerpt.isEmpty { out += "  \(String(excerpt.prefix(300)))\n" }
        }
        return out
    }

    private func day(_ date: String?) -> String {
        let cal = Calendar.current
        let target: Date?
        if let date, let parsed = ISO8601DateFormatter.day.date(from: date + "T12:00:00Z") {
            target = parsed
        } else {
            target = library.items.last?.date
        }
        guard let target else { return "The archive is empty." }
        let items = library.items.filter { cal.isDate($0.date, inSameDayAs: target) }
        guard !items.isEmpty else { return "Nothing was captured that day." }

        var seconds: [String: TimeInterval] = [:]
        for p in items where !p.app.isEmpty { seconds[p.app, default: 0] += max(p.dwell, 30) }
        let ranked = seconds.sorted { $0.value > $1.value }.prefix(6)
        var out = "\(items.count) moments on \(stamp(target, dayOnly: true)).\n"
        for (app, s) in ranked { out += "- \(app): about \(Int(s / 60)) minutes\n" }
        let windows = Dictionary(grouping: items.filter { !$0.window.isEmpty }, by: \.window)
            .sorted { $0.value.count > $1.value.count }.prefix(5)
        if !windows.isEmpty {
            out += "Busiest windows:\n"
            for (w, ps) in windows { out += "- \(String(w.prefix(80))) (\(ps.count) moments)\n" }
        }
        return out
    }

    private func meetings() -> String {
        guard !library.meetings.isEmpty else { return "No meetings were detected." }
        var out = ""
        for m in library.meetings {
            let lines = library.transcripts[m.id]?.count ?? 0
            out += "- \(m.title ?? "Untitled") · \(stamp(m.start)) · "
            out += lines > 0 ? "\(lines) transcript segments\n" : "no transcript\n"
        }
        return out
    }

    private func transcript(_ title: String) -> String {
        let t = title.lowercased()
        let match = library.meetings.first { ($0.title ?? "").lowercased().contains(t) }
            ?? library.meetings.last
        guard let match, let lines = library.transcripts[match.id], !lines.isEmpty else {
            return "No transcript for that meeting."
        }
        var out = "\(match.title ?? "Untitled"), \(stamp(match.start)):\n"
        for l in lines.prefix(60) {
            out += "\(l.speaker): \(l.text)\n"
        }
        return out
    }

    private func stamp(_ d: Date, dayOnly: Bool = false) -> String {
        d.formatted(dayOnly ? .dateTime.weekday(.wide).month().day()
                            : .dateTime.month().day().hour().minute())
    }
}

private extension ISO8601DateFormatter {
    static let day = ISO8601DateFormatter()
}
