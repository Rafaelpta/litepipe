import SwiftUI
import AppKit

@main
struct PhotosCloneApp: App {
    @State private var library = ContextLibrary()
    @State private var nav = NavigationState()
    @State private var sel = SelectionModel()

    init() {
        // `swift run` launches a bare executable with no bundle — promote it to a
        // regular, focusable app so the window comes to the front with a menu bar.
        NSApplication.shared.setActivationPolicy(.regular)
        // Dev convenience: PC_DARK=1 swift run → force dark appearance for QA.
        if ProcessInfo.processInfo.environment["PC_DARK"] != nil {
            NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environment(library)
                .environment(nav)
                .environment(sel)
                .task { Thumbs.shared.prewarm(library.items) }
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .pasteboard) {
                Button("Select All") {
                    let ids = library.photos(for: nav.sidebarItem,
                                             search: nav.searchText,
                                             favoritesOnly: nav.favoritesOnly).map(\.id)
                    sel.selectAll(ids)
                }
                .keyboardShortcut("a")
                Button("Deselect All") {
                    sel.clear()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            }
        }
    }
}
