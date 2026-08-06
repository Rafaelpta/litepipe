import Foundation
import Observation

@Observable
final class NavigationState {
    var sidebarItem: SidebarItem = .timeline
    var viewMode: ViewMode = .days
    var openedPhotoID: UUID?
    /// Whether the grid↔detail hero (matchedGeometryEffect) is engaged.
    /// Turned off during prev/next crossfades so the outgoing image doesn't fly back to its cell.
    var heroActive = true
    var zoomLevel: Double = 0.42
    var showInspector = false
    var searchText = ""
    var favoritesOnly = false
    /// Moments (folded, furniture removed) vs the raw capture stream.
    /// The two side by side are the clearest way to show what the folding buys.
    var rawMode = false
    /// One-shot programmatic scroll request consumed by GridView.
    var scrollTarget: UUID?

    // Sidebar disclosure state lives here (not in the view) so it survives
    // any re-creation of SidebarView when the selection changes.
    var extractedExpanded = true
    var sourcesExpanded = true
    var notebooksExpanded = false
    var pipesExpanded = false
    var agentMemoryExpanded = true
    var sharedContextsExpanded = true
    var firewallExpanded = true

    // Capture control. The keyboard shortcut stays the primary toggle; this is
    // the visible state, so the user is never guessing whether it is recording.
    /// Nil while capturing. A date means paused until then; `.distantFuture`
    /// means paused until the app is relaunched.
    var pausedUntil: Date?

    var capturePaused: Bool {
        guard let until = pausedUntil else { return false }
        return until > Date()
    }

    /// Pass nil to pause until the next launch. The duration is kept so the
    /// pause can expire on its own; the pill deliberately does not show it.
    func pauseCapture(for seconds: TimeInterval?) {
        pausedUntil = seconds.map { Date().addingTimeInterval($0) } ?? .distantFuture
    }

    func resumeCapture() { pausedUntil = nil }
}
