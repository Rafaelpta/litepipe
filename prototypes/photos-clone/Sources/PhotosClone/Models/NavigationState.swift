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
}
