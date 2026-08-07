import Foundation
import Observation

@Observable
final class ContextLibrary {
    private(set) var items: [Photo] = []          // ascending by time
    private(set) var meetings: [ContextDB.Meeting] = []
    private(set) var transcripts: [Int64: [ContextDB.TranscriptLine]] = [:]
    private(set) var uiEventCount = 0
    private(set) var elementCount = 0
    private(set) var loadError: String?
    /// Size of the archive on disk, shown where a competitor shows a plan tier.
    private(set) var archiveSize: String?
    /// frame id → the sentence that matched the current query, from FTS5 snippet().
    private(set) var searchHits: [Int64: String] = [:]
    private var lastQuery = ""


    /// Named slices in the Sharing section. Real archives have no shares yet, so
    /// these stand in for what a share would scope to.
    let shareNames = ["Team Standup", "Acme Support", "Research Panel"]
    let memoryTargets = ["CLAUDE.md", "AGENTS.md"]
    let pipeNames = ["Day Recap", "Standup", "Meeting Summary"]

    /// Notebooks are derived from the busiest hosts, so they name real work.
    private(set) var notebookNames: [String] = []

    private(set) var rawMode = false

    init() { reload() }

    func setRawMode(_ on: Bool) {
        guard on != rawMode else { return }
        rawMode = on
        reload()
    }

    func reload() {
        let load = ContextDB.load(raw: rawMode)
        items = load.items
        meetings = load.meetings
        transcripts = load.transcripts
        uiEventCount = load.uiEventCount
        elementCount = load.elementCount
        loadError = load.error
        notebookNames = topHosts(4)
        archiveSize = Self.diskSize(ContextDB.defaultPath)
    }

    private static func diskSize(_ path: String) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let bytes = attrs[.size] as? Int64 else { return nil }
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useMB, .useGB]
        return f.string(fromByteCount: bytes)
    }

    private func topHosts(_ n: Int) -> [String] {
        let counts = Dictionary(grouping: items.compactMap(\.host), by: { $0 })
            .mapValues(\.count)
        return counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .prefix(n).map(\.key)
    }

    func photo(_ id: UUID) -> Photo? { items.first { $0.id == id } }

    /// The audio recorded while this moment was on screen — not a transcript of
    /// the screen itself. Scoped to the moment's own span, because a three-minute
    /// moment inside a two-hour call should not show two hours of talk.
    func transcript(for photo: Photo) -> [ContextDB.TranscriptLine] {
        guard let mid = photo.meetingId, let all = transcripts[mid] else { return [] }
        let from = photo.date.addingTimeInterval(-30)
        let to = photo.lastSeen.addingTimeInterval(30)
        return all.filter { $0.at >= from && $0.at <= to }
    }

    /// Which meeting was running, so the inspector can name it.
    func meeting(for photo: Photo) -> ContextDB.Meeting? {
        guard let mid = photo.meetingId else { return nil }
        return meetings.first { $0.id == mid }
    }

    // MARK: - Filtering

    /// Displays seen in the archive, in a stable order, for the picker.
    var monitors: [String] {
        Array(Set(items.compactMap(\.monitor))).sorted()
    }

    /// Pass a display to see only that screen. With two monitors the engine
    /// writes a row per screen at the same instant, both carrying the focused
    /// window's text — so without this the grid shows every window twice, once
    /// under a picture of the other display.
    func photos(for item: SidebarItem?, search: String, favoritesOnly: Bool,
                monitor: String? = nil) -> [Photo] {
        var base: [Photo]
        if item == .recentlyDeleted {
            base = items.filter { $0.isDeleted }
        } else {
            let visible = items.filter { !$0.isDeleted && !$0.isHidden }
            switch item {
            // Capture
            case .timeline, .none: base = visible
            case .highlights:     base = visible.filter { $0.isFavorite }
            case .places:         base = visible.filter { $0.host != nil }
            case .today:
                let lastDay = visible.last.map { Calendar.current.startOfDay(for: $0.date) }
                base = visible.filter { p in
                    guard let lastDay else { return false }
                    return Calendar.current.isDate(p.date, inSameDayAs: lastDay)
                }
            // Collections
            case .dayRecaps:      base = dayRepresentatives(visible)
            case .people:         base = visible.filter { $0.meetingId != nil }
            case .meetings:       base = visible.filter { $0.meetingId != nil || $0.source == .meeting }
            case .sessions:       base = sessionStarts(visible)
            case .activity:       base = visible.filter { $0.captureTrigger == "app_switch" || $0.captureTrigger == "window_focus" }
            // Extracted — plain rules over the captured text, no model involved
            case .extracted:      base = visible.filter { $0.textLength > 0 }
            case .decisions:      base = visible.filter { matches($0, ["decid", "we should", "let's go with", "agreed", "vamos", "decisão"]) }
            case .actionItems:    base = visible.filter { matches($0, ["todo", "to-do", "next step", "action item", "follow up", "tarefa"]) }
            case .questions:      base = visible.filter { $0.excerpt.contains("?") }
            case .codeSnippets:   base = visible.filter { $0.source == .terminal || $0.source == .editor }
            case .links:          base = visible.filter { $0.url != nil }
            case .errors:         base = visible.filter { matches($0, ["error", "exception", "failed", "traceback", "fatal", "panic:"]) }
            case .redacted:       base = visible.filter { matches($0, ["password", "secret", "api key", "token", "senha"]) }
            // Sources
            case .sources:        base = visible
            case .screen:         base = visible.filter { $0.hasImage }
            case .microphone:     base = visible.filter { $0.meetingId != nil }
            case .systemAudio:    base = visible.filter { $0.source == .meeting }
            case .keyboardClicks: base = visible.filter { ["typing_pause", "key_press", "click"].contains($0.captureTrigger) }
            case .browser:        base = visible.filter { $0.source == .browser }
            case .terminal:       base = visible.filter { $0.source == .terminal }
            case .editor:         base = visible.filter { $0.source == .editor }
            case .messaging:      base = visible.filter { $0.source == .chat }
            case .email:          base = visible.filter { $0.source == .email }
            case .documents:      base = visible.filter { $0.source == .notes || $0.source == .files }
            case .design:         base = visible.filter { $0.source == .design }
            case .notebooksRoot:
                base = visible.filter { p in notebookNames.contains(p.host ?? "") }
            case .notebook(let name): base = visible.filter { $0.host == name }
            case .pipesRoot:      base = dayRepresentatives(visible)
            case .pipe(let name): base = pipeSlice(name, visible)
            // Memory
            case .agentMemory:    base = visible.filter { $0.textLength > 2000 }
            case .facts:          base = visible.filter { $0.textLength > 4000 }
            case .playbooks:      base = visible.filter { $0.source == .terminal && $0.textLength > 1500 }
            case .sops:           base = visible.filter { $0.source == .notes || $0.source == .editor }
            case .memoryTarget(let name):
                base = visible.filter { $0.textLength > 2000 && (name == "CLAUDE.md" ? $0.source == .terminal || $0.source == .editor : $0.source != .terminal) }
            // Sharing
            case .sharedContexts: base = visible.filter { $0.meetingId != nil || $0.source == .editor }
            case .accessLog:      base = Array(visible.suffix(60))
            case .share(let name): base = shareSlice(name, visible)
            case .firewall, .firewallRules:
                base = visible.filter { $0.source == .chat || $0.source == .email }
            // The assistant has no grid of its own; it reads whatever else is selected.
            case .assistant:      base = []
            case .connectedApps:  base = visible.filter { $0.source == .terminal || $0.source == .editor }
            case .blocked:        base = visible.filter { matches($0, ["password", "secret", "api key", "token", "senha"]) }
            case .requests:       base = Array(visible.filter { $0.source == .meeting }.suffix(20))
            case .recentlyDeleted: base = []
            }
        }
        if favoritesOnly { base = base.filter { $0.isFavorite } }
        if let monitor { base = base.filter { $0.monitor == monitor } }

        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return base }

        // Metadata match is cheap and in memory. Full-text match goes through the
        // engine's FTS5 index, which reaches text we never loaded — the tail of a
        // 45k-character terminal buffer, the middle of a chat pane.
        refreshSearch(q)
        let lower = q.lowercased()
        return base.filter { p in
            searchHits[p.frameId] != nil
                || p.app.lowercased().contains(lower)
                || p.window.lowercased().contains(lower)
                || (p.host?.lowercased().contains(lower) ?? false)
                || p.source.label.lowercased().contains(lower)
        }
    }

    private func refreshSearch(_ q: String) {
        guard q != lastQuery else { return }
        lastQuery = q
        searchHits = ContextDB.search(q)
    }

    /// The sentence that made this capture match, if the match came from full text.
    func matchSnippet(_ p: Photo) -> String? {
        guard let s = searchHits[p.frameId], !s.isEmpty else { return nil }
        return s
    }

    private func matches(_ p: Photo, _ needles: [String]) -> Bool {
        let hay = (p.excerpt + " " + p.window).lowercased()
        return needles.contains { hay.contains($0) }
    }

    /// One representative capture per day — the longest text of that day, which is
    /// usually the most substantial thing that happened.
    private func dayRepresentatives(_ list: [Photo]) -> [Photo] {
        let cal = Calendar.current
        var best: [Date: Photo] = [:]
        for p in list {
            let day = cal.startOfDay(for: p.date)
            if let cur = best[day], cur.textLength >= p.textLength { continue }
            best[day] = p
        }
        return best.values.sorted { $0.date < $1.date }
    }

    /// A session starts whenever the app changes or more than 10 minutes pass.
    private func sessionStarts(_ list: [Photo]) -> [Photo] {
        var out: [Photo] = []
        var lastApp = ""
        var lastAt = Date.distantPast
        for p in list {
            if p.app != lastApp || p.date.timeIntervalSince(lastAt) > 600 {
                out.append(p)
            }
            lastApp = p.app
            lastAt = p.date
        }
        return out
    }

    private func pipeSlice(_ name: String, _ list: [Photo]) -> [Photo] {
        switch name {
        case "Day Recap":       dayRepresentatives(list)
        case "Standup":         sessionStarts(list).filter { $0.source == .editor || $0.source == .terminal }
        case "Meeting Summary": list.filter { $0.meetingId != nil }
        default:                []
        }
    }

    private func shareSlice(_ name: String, _ list: [Photo]) -> [Photo] {
        switch name {
        case "Team Standup":   sessionStarts(list).filter { $0.source == .editor || $0.source == .terminal }
        case "Acme Support":   list.filter { $0.meetingId != nil }
        case "Research Panel": list.filter { $0.source == .browser && $0.host != nil }
        default:               []
        }
    }

    // MARK: - Grouping

    func daySections(_ list: [Photo]) -> [DaySection] {
        let cal = Calendar.current
        var order: [Date] = []
        var buckets: [Date: [Photo]] = [:]
        for p in list {
            let day = cal.startOfDay(for: p.date)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(p)
        }
        return order.map { day in
            let ps = buckets[day]!
            let places = ps.compactMap(\.place)
            let top = Dictionary(grouping: places, by: { $0 }).max { $0.value.count < $1.value.count }?.key
            return DaySection(id: day, title: Self.dayTitle(day), subtitle: top, photos: ps)
        }
    }

    static func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        if cal.component(.year, from: day) == cal.component(.year, from: Date()) {
            return day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        }
        return day.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    func monthGroups(_ list: [Photo]) -> [(month: Date, photos: [Photo])] {
        group(list, by: [.year, .month]).map { (month: $0.0, photos: $0.1) }
    }

    func yearGroups(_ list: [Photo]) -> [(year: Date, photos: [Photo])] {
        group(list, by: [.year]).map { (year: $0.0, photos: $0.1) }
    }

    private func group(_ list: [Photo], by comps: Set<Calendar.Component>) -> [(Date, [Photo])] {
        let cal = Calendar.current
        var order: [Date] = []
        var buckets: [Date: [Photo]] = [:]
        for p in list {
            let key = cal.date(from: cal.dateComponents(comps, from: p.date))!
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(p)
        }
        return order.map { ($0, buckets[$0]!) }
    }

    // MARK: - Mutations (session-only; the archive is never written to)

    func toggleFavorite(_ ids: Set<UUID>) {
        let allFav = items.filter { ids.contains($0.id) }.allSatisfy(\.isFavorite)
        for i in items.indices where ids.contains(items[i].id) { items[i].isFavorite = !allFav }
    }

    func moveToTrash(_ ids: Set<UUID>) {
        for i in items.indices where ids.contains(items[i].id) { items[i].isDeleted = true }
    }

    func restore(_ ids: Set<UUID>) {
        for i in items.indices where ids.contains(items[i].id) { items[i].isDeleted = false }
    }

    func eraseForever(_ ids: Set<UUID>) { items.removeAll { ids.contains($0.id) } }

    func hide(_ ids: Set<UUID>) {
        for i in items.indices where ids.contains(items[i].id) { items[i].isHidden.toggle() }
    }

    func duplicate(_ ids: Set<UUID>) { /* not meaningful for captured context */ }
}
