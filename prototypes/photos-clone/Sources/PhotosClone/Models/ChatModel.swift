import Foundation
import Observation

/// A turn in the conversation. Assistant turns carry the moments the answer was
/// built from, so every claim stays one click from the screen it came from.
struct ChatTurn: Identifiable, Hashable {
    enum Role { case you, assistant }
    let id = UUID()
    let role: Role
    let text: String
    var citations: [Photo] = []
    var searchedCount: Int = 0
}

/// Answers questions over the whole archive. Retrieval is real — the same FTS
/// index and the same moments the grid shows. The composition is deterministic
/// rather than a model call, so the prototype answers offline and never invents
/// anything the archive does not contain.
@Observable
final class ChatModel {
    var turns: [ChatTurn] = []
    var pending = false
    var draft = ""

    /// Openers built from the archive, so the empty state is never generic.
    func suggestions(_ lib: ContextLibrary) -> [String] {
        var out = ["O que eu fiz ontem?", "Resumo da semana"]
        if !lib.meetings.isEmpty { out.append("Minhas reuniões") }
        if let host = lib.notebookNames.first { out.append("O que eu vi em \(host)?") }
        return out
    }

    func ask(_ question: String, lib: ContextLibrary) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !pending else { return }
        turns.append(ChatTurn(role: .you, text: q))
        draft = ""
        pending = true

        // A beat of thinking, so the answer does not snap in before the question
        // has been read. Retrieval itself is fast enough to be invisible.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            turns.append(answer(to: q, lib: lib))
            pending = false
        }
    }

    func reset() { turns = []; draft = "" }

    // MARK: - Answering

    private func answer(to q: String, lib: ContextLibrary) -> ChatTurn {
        let all = lib.items.filter { !$0.isDeleted && !$0.isHidden }
        guard !all.isEmpty else {
            return ChatTurn(role: .assistant,
                            text: "Não há nada capturado neste arquivo ainda.")
        }
        let lower = q.lowercased()

        if let day = dayReferenced(lower, in: all) {
            return recap(for: day, all: all, lib: lib)
        }
        if lower.contains("semana") || lower.contains("week") {
            return weekRecap(all, lib: lib)
        }
        if lower.contains("reuni") || lower.contains("meeting") || lower.contains("call") {
            return meetingsAnswer(all, lib: lib)
        }
        return searchAnswer(q, all: all, lib: lib)
    }

    // MARK: Intents

    private func dayReferenced(_ q: String, in all: [Photo]) -> Date? {
        let cal = Calendar.current
        let days = Set(all.map { cal.startOfDay(for: $0.date) }).sorted()
        if q.contains("hoje") || q.contains("today") { return days.last }
        if q.contains("ontem") || q.contains("yesterday") {
            return days.count >= 2 ? days[days.count - 2] : days.last
        }
        return nil
    }

    private func recap(for day: Date, all: [Photo], lib: ContextLibrary) -> ChatTurn {
        let cal = Calendar.current
        let items = all.filter { cal.isDate($0.date, inSameDayAs: day) }
        guard !items.isEmpty else {
            return ChatTurn(role: .assistant,
                            text: "Nada foi capturado em \(Self.dayName(day)).",
                            searchedCount: all.count)
        }
        var text = "**\(Self.dayName(day))** — \(Self.span(items)).\n\n"
        text += appLine(items)
        if let m = meetingLine(items, lib: lib) { text += "\n\n" + m }
        if let t = taskLine(items) { text += "\n\n" + t }
        if let s = siteLine(items) { text += "\n\n" + s }
        return ChatTurn(role: .assistant, text: text,
                        citations: highlights(items), searchedCount: all.count)
    }

    private func weekRecap(_ all: [Photo], lib: ContextLibrary) -> ChatTurn {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: all) { cal.startOfDay(for: $0.date) }
        var text = "Tenho \(all.count) momentos em \(byDay.count) dias.\n\n"
        for day in byDay.keys.sorted() {
            let items = byDay[day]!
            let apps = topApps(items, limit: 3).map(\.0).joined(separator: ", ")
            text += "**\(Self.dayName(day))** · \(Self.span(items)) · \(items.count) momentos"
            text += apps.isEmpty ? "\n" : " — \(apps)\n"
        }
        if let t = taskLine(all) { text += "\n" + t }
        return ChatTurn(role: .assistant, text: text,
                        citations: highlights(all), searchedCount: all.count)
    }

    private func meetingsAnswer(_ all: [Photo], lib: ContextLibrary) -> ChatTurn {
        guard !lib.meetings.isEmpty else {
            return ChatTurn(role: .assistant,
                            text: "Nenhuma reunião foi detectada neste arquivo.",
                            searchedCount: all.count)
        }
        var text = ""
        for m in lib.meetings {
            let title = m.title ?? "Reunião sem título"
            let mins = m.end.map { Int($0.timeIntervalSince(m.start) / 60) }
            let lines = lib.transcripts[m.id]?.count ?? 0
            text += "**\(title)** — \(Self.dayName(m.start)), "
            text += m.start.formatted(date: .omitted, time: .shortened)
            if let mins { text += ", \(mins) min" }
            text += ".\n"
            if lines > 0 {
                let mine = lib.transcripts[m.id]?.filter(\.isMe).count ?? 0
                text += "\(lines) trechos de áudio, \(mine) do seu microfone.\n"
                if mine == lines || lines - mine <= 1 {
                    text += "_O outro lado praticamente não foi gravado._\n"
                }
            }
            text += "\n"
        }
        let cited = all.filter { $0.meetingId != nil }
        return ChatTurn(role: .assistant, text: text,
                        citations: Array(cited.prefix(6)), searchedCount: all.count)
    }

    /// Anything else goes through the engine's own full-text index, so the answer
    /// reaches text the grid never loaded.
    private func searchAnswer(_ q: String, all: [Photo], lib: ContextLibrary) -> ChatTurn {
        let hits = ContextDB.search(q)
        var found = all.filter { hits[$0.frameId] != nil }
        if found.isEmpty {
            let lower = q.lowercased()
            found = all.filter {
                $0.window.lowercased().contains(lower)
                    || $0.app.lowercased().contains(lower)
                    || ($0.host?.lowercased().contains(lower) ?? false)
                    || $0.excerpt.lowercased().contains(lower)
            }
        }
        guard !found.isEmpty else {
            return ChatTurn(role: .assistant,
                            text: "Não encontrei nada sobre isso nos \(all.count) momentos guardados.",
                            searchedCount: all.count)
        }
        var text = "Achei **\(found.count)** momentos sobre isso"
        if let first = found.first, let last = found.last {
            text += ", de \(Self.dayName(first.date)) a \(Self.dayName(last.date))"
        }
        text += ".\n\n"
        text += appLine(found)
        if let snippet = found.compactMap({ hits[$0.frameId] }).first(where: { !$0.isEmpty }) {
            text += "\n\nTrecho que casou:\n_\(snippet.replacingOccurrences(of: "\n", with: " "))_"
        }
        return ChatTurn(role: .assistant, text: text,
                        citations: Array(found.suffix(6).reversed()), searchedCount: all.count)
    }

    // MARK: Sentence builders

    private func appLine(_ items: [Photo]) -> String {
        let apps = topApps(items, limit: 4)
        guard !apps.isEmpty else { return "" }
        let parts = apps.map { "\($0.0) (\($0.1))" }
        return "Onde você esteve: " + parts.joined(separator: ", ") + "."
    }

    private func meetingLine(_ items: [Photo], lib: ContextLibrary) -> String? {
        let ids = Set(items.compactMap(\.meetingId))
        guard !ids.isEmpty else { return nil }
        let names = lib.meetings.filter { ids.contains($0.id) }
            .map { $0.title ?? "reunião sem título" }
        return "Reuniões: " + names.joined(separator: ", ") + "."
    }

    /// Claude Code writes the task name into the terminal title, which turns the
    /// terminal into a work log nobody had to keep.
    private func taskLine(_ items: [Photo]) -> String? {
        // A Claude Code title reads "<project> — <task> — <process> ◂ claude".
        // Only those carry a task name; a bare "<project> — swift-build ▸ swiftc"
        // is the compiler talking, not a description of the work.
        var tasks: [String] = []
        for p in items where p.source == .terminal && p.window.contains("◂ claude") {
            let parts = p.window.components(separatedBy: " — ")
            guard parts.count >= 3 else { continue }
            let task = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " ✳⠂⠐⠈⠁⠠⢀"))
            if task.count > 6, !task.contains("▸"), !tasks.contains(task) { tasks.append(task) }
        }
        guard !tasks.isEmpty else { return nil }
        return "No terminal: " + tasks.prefix(5).joined(separator: " · ") + "."
    }

    private func siteLine(_ items: [Photo]) -> String? {
        let hosts = items.compactMap(\.host).filter { !$0.contains("whatsapp") }
        let top = Dictionary(grouping: hosts, by: { $0 }).mapValues(\.count)
            .sorted { $0.value > $1.value }.prefix(4).map(\.key)
        guard !top.isEmpty else { return nil }
        return "Sites: " + top.joined(separator: ", ") + "."
    }

    private func topApps(_ items: [Photo], limit: Int) -> [(String, String)] {
        let byApp = Dictionary(grouping: items.filter { !$0.app.isEmpty }, by: \.app)
        return byApp
            .map { ($0.key, $0.value.reduce(0.0) { $0 + max($1.dwell, 30) }) }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { ($0.0, Self.duration($0.1)) }
    }

    /// The moments worth showing: prefer real content, then screenshots.
    private func highlights(_ items: [Photo]) -> [Photo] {
        let rich = items.filter { !$0.isThin }.sorted { $0.contentLineCount > $1.contentLineCount }
        let shots = items.filter(\.hasImage)
        var out: [Photo] = []
        for p in rich.prefix(4) where !out.contains(p) { out.append(p) }
        for p in shots.prefix(2) where !out.contains(p) { out.append(p) }
        return out
    }

    // MARK: Formatting

    static func dayName(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Hoje" }
        if cal.isDateInYesterday(d) { return "Ontem" }
        return d.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    static func span(_ items: [Photo]) -> String {
        guard let a = items.map(\.date).min(), let b = items.map(\.lastSeen).max() else { return "" }
        let f = Date.FormatStyle(date: .omitted, time: .shortened)
        return "\(a.formatted(f)) às \(b.formatted(f))"
    }

    static func duration(_ secs: TimeInterval) -> String {
        let m = Int(secs / 60)
        if m >= 60 { return "\(m / 60)h\(String(format: "%02d", m % 60))" }
        return "\(max(m, 1)) min"
    }
}
