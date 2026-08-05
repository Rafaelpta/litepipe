import Foundation
import Observation

@Observable
final class NavigationState {
    var sidebarItem: SidebarItem = .library
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
    var utilitiesExpanded = true
    var mediaTypesExpanded = true
    var albumsExpanded = false
    var projectsExpanded = false
    var sharedAlbumsExpanded = true
}
