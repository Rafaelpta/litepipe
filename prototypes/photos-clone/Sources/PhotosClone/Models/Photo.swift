import Foundation

enum PhotoKind: String, CaseIterable {
    case landscape, sunset, portrait, food, pet, city, beach, forest, screenshot

    var searchName: String {
        switch self {
        case .landscape: "landscape mountains"
        case .sunset: "sunset sky"
        case .portrait: "portrait people"
        case .food: "food restaurant"
        case .pet: "pet dog cat"
        case .city: "city buildings"
        case .beach: "beach sea ocean"
        case .forest: "forest trees nature"
        case .screenshot: "screenshot"
        }
    }
}

struct Photo: Identifiable, Hashable {
    let id: UUID
    let seed: UInt64
    let date: Date
    let kind: PhotoKind
    let location: String?
    var isFavorite: Bool
    var isDeleted: Bool
    var isHidden: Bool
    let pixelWidth: Int
    let pixelHeight: Int
    let fileName: String
    let camera: String?
    let aperture: String?
    let iso: Int?
    let focalLength: String?
    let shutter: String?
    let megabytes: Double

    var aspect: CGFloat { CGFloat(pixelWidth) / CGFloat(pixelHeight) }
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
    // Capture — the raw stream
    case timeline, highlights, places, today, recentlyDeleted
    // Collections — derived structure
    case dayRecaps, people, meetings, sessions, activity
    case extracted, decisions, actionItems, questions, codeSnippets, links, errors, redacted
    case sources, screen, microphone, systemAudio, keyboardClicks, browser, terminal,
         editor, chat, email, documents, design
    case notebooksRoot, notebook(String), pipesRoot, pipe(String)
    // Memory — distilled, agent-facing
    case agentMemory, facts, playbooks, sops, memoryTarget(String)
    // Sharing — the context firewall: what crosses the machine boundary, to whom
    case sharedContexts, accessLog, share(String)
    case firewall, firewallRules, connectedApps, blocked
    case requests

    var displayName: String {
        switch self {
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
        case .chat: "Chat"
        case .email: "Email"
        case .documents: "Documents"
        case .design: "Design"
        case .notebooksRoot: "Notebooks"
        case .notebook(let name): name
        case .pipesRoot: "Pipes"
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
