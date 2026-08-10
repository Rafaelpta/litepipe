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
    /// Open from the start. The picture is half of a capture and the text read
    /// off it is the other half; keeping that behind a toolbar button made the
    /// app look like a picture viewer.
    var showInspector = true
    var searchText = ""
    var favoritesOnly = false
    /// Which display to show, or nil for all of them. Only surfaced when the
    /// archive holds more than one.
    var monitor: String?
    /// Moments (folded, furniture removed) vs the raw capture stream.
    /// The two side by side are the clearest way to show what the folding buys.
    var rawMode = false
    /// One-shot programmatic scroll request consumed by GridView.
    var scrollTarget: UUID?
    /// Bumped whenever the sidebar selection changes so the grid takes focus.
    /// Without it the sidebar stays first responder and macOS paints the row
    /// with the emphasised accent fill; Photos shows the grey one because focus
    /// has already moved to the content.
    var focusContentToken = 0

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

    /// Set by the app so these controls drive the capture engine instead of only
    /// the display. Left nil by the prototype, which has no engine to drive:
    /// there the pill is a mock and says so by doing nothing to the machine.
    var onPause: ((TimeInterval?) -> Void)?
    var onResume: (() -> Void)?

    /// Pass nil to pause until the next launch. The duration is kept so the
    /// pause can expire on its own; the pill deliberately does not show it.
    func pauseCapture(for seconds: TimeInterval?) {
        pausedUntil = seconds.map { Date().addingTimeInterval($0) } ?? .distantFuture
        onPause?(seconds)
    }

    func resumeCapture() {
        pausedUntil = nil
        onResume?()
    }

    /// Why capture stopped when nobody asked it to: a missing permission, a
    /// crashed engine. Nil while capturing and nil during a deliberate pause, so
    /// an empty archive can tell "off because you said so" apart from "off, and
    /// there is something for you to fix".
    var engineTrouble: String?

    /// The engine is the authority on whether capture is running: the chord, the
    /// notch and a crash all change it behind the UI's back. The app mirrors it
    /// here rather than letting two truths drift apart.
    func reflectEngine(paused: Bool) {
        if paused {
            if pausedUntil == nil { pausedUntil = .distantFuture }
        } else {
            pausedUntil = nil
        }
    }
}
