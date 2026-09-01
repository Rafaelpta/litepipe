import AppKit
import SwiftUI

/// Two scenes over one archive: the window and the menu bar item. The AppKit
/// delegate keeps what predates them, which is now just the engine process and
/// the drag helper the permission flow needs.
@main
struct LitepipeApp: App {
    static let archiveWindowID = "archive"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    /// Held here rather than inside a view: the window and the menu bar item are
    /// two scenes reading one archive, and the menu has to know whether capture
    /// is running before anybody opens the window.
    @State private var models = ArchiveModels.shared

    var body: some Scene {
        Window("litepipe", id: Self.archiveWindowID) {
            ArchiveWindow(models: models)
        }
        .defaultSize(width: 1280, height: 800)
        .commands { ArchiveCommands() }

        // The app runs all day with its window closed most of it, so the menu
        // bar is where it actually lives: the mark, the last meeting, and the
        // pause control within reach of any screen.
        MenuBarExtra {
            MenuBarMenu()
                .environment(models.library)
                .environment(models.nav)
        } label: {
            MenuBarLabel(paused: models.nav.capturePaused)
        }
    }
}

/// The mark in the menu bar, and the one place the app can get hold of
/// `openWindow`.
///
/// Building a window is something only its scene can do, and both the Dock
/// delegate and the menu live outside the scene graph. This label lives inside
/// it and is rendered for as long as the app runs, so it hands the action out
/// to them. Without it, closing the window left no way back in: the Dock icon
/// and "Open litepipe" both looked for a window that no longer existed.
private struct MenuBarLabel: View {
    let paused: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: MenuBarIcon.image(paused: paused))
            .onAppear {
                let open = { openWindow(id: LitepipeApp.archiveWindowID) }
                ArchiveOpener.open = open
                MenuBarMenu.reopen = open
            }
    }
}

enum ArchiveOpener {
    static var open: (() -> Void)?

    /// Bring the archive up whether or not a window still exists.
    static func run() {
        NSApp.activate(ignoringOtherApps: true)
        open?()
        DispatchQueue.main.async {
            AppDelegate.archiveWindow()?.makeKeyAndOrderFront(nil)
        }
    }
}

/// Reopening a closed window needs `openWindow`, which only exists inside the
/// scene graph — hence a Commands type rather than a call from the delegate.
struct ArchiveCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Without this the window exists and nothing can open it: the app had
        // no Settings command at all, so ⌘, did nothing.
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { SettingsController.shared.show() }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(after: .windowArrangement) {
            Button("litepipe Archive") {
                openWindow(id: LitepipeApp.archiveWindowID)
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("0", modifiers: .command)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    /// Still here without the notch: the permission flow tells people to drag the
    /// app into a Settings list, and this is the thing they drag.
    private let dragHelper = DragHelperController()
    let engine = EngineController.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Two copies (e.g. the installed app plus a dev build opened via
        // Spotlight) fight over the engine port, data dir and log. Keep only
        // the first instance; hand focus to it and quit.
        let others = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? "ai.ottic.litepipe"
        ).filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        // A launch that ends in silence is impossible to tell from a crash, and
        // this guard is the one place the app quits before doing anything.
        litepipeLog("launch: bundle=\(Bundle.main.bundleIdentifier ?? "nil") "
                    + "path=\(Bundle.main.bundlePath) others=\(others.count)")
        if !others.isEmpty {
            others.first?.activate()
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.regular) // Dock icon so the app is visible and quittable

        // Never trust the sticky "complete" flag alone: permissions can be revoked
        // or reset after onboarding finished. Capture only runs with live grants.
        litepipeLog("launch: onboarded=\(UserDefaults.standard.bool(forKey: "onboarding.complete.v1")) "
                    + "permissions=\(Permissions.allRequiredGranted())")
        if UserDefaults.standard.bool(forKey: "onboarding.complete.v1"),
           Permissions.allRequiredGranted() {
            engine.start()
        }
        // No else: the permission flow lives in the window, which opens on it
        // when the grants are missing.

        let nc = NotificationCenter.default
        nc.addObserver(forName: .litepipeShowDragHelper, object: nil, queue: .main) { [weak self] _ in
            self?.dragHelper.show()
        }
        nc.addObserver(forName: .litepipeHideDragHelper, object: nil, queue: .main) { [weak self] _ in
            self?.dragHelper.hide()
        }
        // The window posts this when the last grant lands.
        nc.addObserver(forName: .litepipeOnboardingDone, object: nil, queue: .main) { [weak self] _ in
            self?.dragHelper.hide()
            self?.engine.start()
        }
    }

    /// The app is a capture engine that happens to have a window, not a document
    /// app. Closing the archive leaves the menu bar item and the engine running,
    /// and under the SwiftUI lifecycle the default is the opposite: the last
    /// window closing takes the whole process with it, silently.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // Without this the posix_spawned engine child outlives the app (holding port
    // 3030 and re-prompting for permissions on the next launch).
    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }

    // Dock click: bring the archive forward. A regular app with no visible
    // window would otherwise do nothing at all.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        ArchiveOpener.run()
        return false
    }

    /// The scene's window, picked out of the set the app owns. The drag helper is
    /// an NSPanel and never becomes main, which is what tells it apart.
    static func archiveWindow() -> NSWindow? {
        NSApp.windows.first { $0.canBecomeMain && !($0 is NSPanel) }
    }
}
