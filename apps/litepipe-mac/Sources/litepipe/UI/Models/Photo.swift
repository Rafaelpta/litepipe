import Foundation

/// What kind of surface the capture came from. Derived from the app name and
/// browser URL at load time — litepipe stores neither, it stores the raw app
/// and window, and this is the cheap classification on top.
enum ContextSource: String, CaseIterable {
    case browser, chat, email, terminal, editor, meeting, notes, files, design, other

    var label: String {
        switch self {
        case .browser: "Browser"
        case .chat: "Messaging"
        case .email: "Email"
        case .terminal: "Terminal"
        case .editor: "Editor"
        case .meeting: "Meeting"
        case .notes: "Documents"
        case .files: "Files"
        case .design: "Design"
        case .other: "Screen"
        }
    }

    var symbol: String {
        switch self {
        case .browser: "safari"
        case .chat: "bubble.left.and.bubble.right"
        case .email: "envelope"
        case .terminal: "terminal"
        case .editor: "curlybraces"
        case .meeting: "person.2.wave.2"
        case .notes: "doc.text"
        case .files: "folder"
        case .design: "paintbrush"
        case .other: "display"
        }
    }

    /// Hue used by the generated text card, so each source reads as its own colour.
    var hue: Double {
        switch self {
        case .browser: 0.58
        case .chat: 0.33
        case .email: 0.60
        case .terminal: 0.0
        case .editor: 0.75
        case .meeting: 0.08
        case .notes: 0.13
        case .files: 0.55
        case .design: 0.88
        case .other: 0.62
        }
    }
}

/// One screen the engine kept. Ten minutes after it was taken, a background
/// worker folds its JPEG into an H.265 chunk — 18x less disk for the same pixels
/// — deletes the file and leaves a pointer behind. From then on the screen only
/// exists as frame `offset` of `videoPath`, and `jpgPath` is nil. That is where
/// almost the whole archive lives: 262 captures are still JPEGs, 10,997 are
/// inside chunks.
struct Shot: Hashable {
    let frameId: Int64
    let at: Date
    let jpgPath: String?
    let videoPath: String?
    let offset: Int
    /// The chunk's own rate, which the engine varies with the capture interval.
    /// Seeking by a constant would land on the wrong screen.
    let fps: Double
}

/// One captured moment. Mirrors a row of `frames` in ~/.litepipe/db.sqlite.
struct Photo: Identifiable, Hashable {
    let id: UUID
    let frameId: Int64
    let date: Date
    let app: String
    let window: String
    let url: String?
    /// Host only, e.g. "web.whatsapp.com". Nil for non-browser captures.
    let host: String?
    let snapshotPath: String?
    /// Every screen this moment folded, in order. A moment is not one picture: you
    /// sat on this window for two minutes and the engine kept forty of them. The
    /// detail view walks them; the grid shows the first.
    let shots: [Shot]
    /// What set off each capture, counted across the whole moment. The first
    /// frame's trigger alone would describe one capture out of sixty and read as
    /// if it described all of them.
    let triggers: [String: Int]
    /// First few hundred characters of what was on screen.
    let excerpt: String
    let textLength: Int
    let source: ContextSource
    let captureTrigger: String
    let textSource: String
    let monitor: String?
    let meetingId: Int64?
    /// How many captures were folded into this moment. The engine writes a frame
    /// on every typing pause, so a screen you sat on for two minutes is one
    /// moment, not forty.
    let repeatCount: Int
    /// Timestamp of the last capture in the moment.
    let lastSeen: Date
    /// Lines the raw captures held before furniture and repeats were dropped.
    let rawLineCount: Int
    /// Lines that survived — the actual content of the moment.
    let contentLineCount: Int
    /// Of those, how many are long enough to be prose rather than a label.
    /// A transcript line runs 40+ characters; a sidebar item is one word.
    let substantiveLineCount: Int
    var isFavorite: Bool
    var isDeleted: Bool
    var isHidden: Bool

    /// Stable seed for the generated card, so a frame always looks the same.
    var seed: UInt64 { UInt64(bitPattern: Int64(frameId &* 2_654_435_761)) }
    var hasImage: Bool { !shots.isEmpty }
    /// The screen that stands for the moment in the grid.
    var coverShot: Shot? { shots.first }
    var dwell: TimeInterval { lastSeen.timeIntervalSince(date) }
    /// Where the capture happened, digitally — used as the day-section subtitle.
    var place: String? { host ?? (app.isEmpty ? nil : app) }

    /// True when nothing on screen was worth reading — a file browser, a message
    /// list nobody opened. Repetition cannot tell a Finder sidebar from a file
    /// listing, but the shape of the text can: in a document 65-93% of lines are
    /// full sentences, in a file browser 0-7% are, and those few are just long
    /// filenames. Measured on the real archive. Thin moments get a one-line
    /// summary instead of forty labels.
    var isThin: Bool {
        substantiveLineCount < 3 || substantiveLineCount * 5 < contentLineCount
    }

    /// What a thin moment says instead of showing its text. The title is already
    /// on the line above, so this describes the state, not the place.
    var activityLine: String {
        switch source {
        case .files:   "Browsed files — nothing read"
        case .email:   "Scanned the inbox — nothing opened"
        case .chat:    "Message list — nothing read"
        case .meeting: "On a call — nothing read on screen"
        case .design:  "Design surface — no text captured"
        default:       "Passed through — nothing read"
        }
    }

    /// Browsers append their own name and the profile to every window title, so
    /// "interview clipping bot - Google Search - Google Chrome - Rafael (ottic.ai)"
    /// is mostly noise. Keep the part that names the page.
    static func shortTitle(_ window: String, app: String, host: String?) -> String {
        guard !window.isEmpty else { return host ?? app }
        var t = window
        for browser in [" - Google Chrome", " - Safari", " - Arc", " - Firefox", " — Firefox"] {
            if let r = t.range(of: browser) { t = String(t[t.startIndex..<r.lowerBound]) }
        }
        if let r = t.range(of: " - Google Search") { t = String(t[t.startIndex..<r.lowerBound]) }
        t = t.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? (host ?? app) : t
    }
}

enum ViewMode: String, CaseIterable, Identifiable {
    case years, months, days, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .years: "Years"
        case .months: "Months"
        case .days: "Days"
        case .all: "All Photos"
        }
    }
}

/// The sidebar is the product's storage model made visible. Three sections, three tiers:
/// Capture is the raw append-only stream, Collections are recomputable indexes over it,
/// Memory is the small distilled layer an agent reads.
enum SidebarItem: Hashable {
    /// Talking to the archive. Sits above everything because it is the one place
    /// you go with a question rather than a place to browse.
    case assistant
    // Capture — the raw stream
    case timeline, highlights, places, today, recentlyDeleted
    // Collections — derived structure
    case dayRecaps, people, meetings, sessions, activity
    case extracted, decisions, actionItems, questions, codeSnippets, links, errors, redacted
    case sources, screen, microphone, systemAudio, keyboardClicks, browser, terminal,
         editor, messaging, email, documents, design
    case notebooksRoot, notebook(String), pipesRoot, pipe(String)
    // Memory — distilled, agent-facing
    case agentMemory, facts, playbooks, sops, memoryTarget(String)
    // Sharing — the context firewall: what crosses the machine boundary, to whom
    case sharedContexts, accessLog, share(String)
    case firewall, firewallRules, connectedApps, blocked
    case requests

    /// The written page this row belongs to, if any. Children answer with their
    /// parent: Facts and SOPs are names for parts of a thing that has not been
    /// built either, so sending them to a filtered grid would dress the same
    /// emptiness up as three different features.
    var page: SidebarItem? {
        switch self {
        case .agentMemory, .facts, .playbooks, .sops, .memoryTarget:
            .agentMemory
        case .firewall, .firewallRules, .connectedApps, .blocked:
            .firewall
        case .sharedContexts, .accessLog, .share:
            .sharedContexts
        case .pipesRoot, .pipe:
            .pipesRoot
        default:
            nil
        }
    }

    /// Nothing to select on a page, so the inspector stays out of its way.
    var isPage: Bool { page != nil }

    var displayName: String {
        switch self {
        case .assistant: "Chat"
        case .timeline: "Timeline"
        case .highlights: "Highlights"
        case .places: "Places"
        case .today: "Today"
        case .recentlyDeleted: "Recently Deleted"
        case .dayRecaps: "Day Recaps"
        case .people: "People"
        case .meetings: "Meetings"
        case .sessions: "Sessions"
        case .activity: "Activity"
        case .extracted: "Extracted"
        case .decisions: "Decisions"
        case .actionItems: "Action Items"
        case .questions: "Questions"
        case .codeSnippets: "Code Snippets"
        case .links: "Links"
        case .errors: "Errors"
        case .redacted: "Redacted"
        case .sources: "Sources"
        case .screen: "Screen"
        case .microphone: "Microphone"
        case .systemAudio: "System Audio"
        case .keyboardClicks: "Keyboard & Clicks"
        case .browser: "Browser"
        case .terminal: "Terminal"
        case .editor: "Editor"
        case .messaging: "Messaging"
        case .email: "Email"
        case .documents: "Documents"
        case .design: "Design"
        case .notebooksRoot: "Notebooks"
        case .notebook(let name): name
        case .pipesRoot: "Workflows"
        case .pipe(let name): name
        case .agentMemory: "Agent Memory"
        case .facts: "Facts"
        case .playbooks: "Playbooks"
        case .sops: "SOPs"
        case .memoryTarget(let name): name
        case .sharedContexts: "Shared Contexts"
        case .accessLog: "Access Log"
        case .share(let name): name
        case .firewall: "Firewall"
        case .firewallRules: "Rules"
        case .connectedApps: "Connected Apps"
        case .blocked: "Blocked"
        case .requests: "Requests"
        }
    }
}

struct DaySection: Identifiable {
    let id: Date
    let title: String
    let subtitle: String?
    let photos: [Photo]
}
