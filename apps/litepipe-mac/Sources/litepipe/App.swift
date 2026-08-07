import AppKit
import SwiftUI

/// The app runs a SwiftUI scene for the archive window and an AppKit delegate for
/// everything that came before it: the engine process, the notch companion, the
/// onboarding panel. Neither one owns the other, and the notch is untouched.
@main
struct LitepipeApp: App {
    static let archiveWindowID = "archive"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    /// Held here rather than inside a view: the window and the menu bar item are
    /// two scenes reading one archive, and the menu has to know whether capture
    /// is running before anybody opens the window.
    @State private var models = ArchiveModels(engine: .shared)

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
            Image(nsImage: MenuBarIcon.image(paused: models.nav.capturePaused))
        }
    }
}

/// Reopening a closed window needs `openWindow`, which only exists inside the
/// scene graph — hence a Commands type rather than a call from the delegate.
struct ArchiveCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
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
        if let archive = Self.archiveWindow() {
            archive.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return false
    }

    /// The scene's window, picked out of the set the app owns. The drag helper is
    /// an NSPanel and never becomes main, which is what tells it apart.
    static func archiveWindow() -> NSWindow? {
        NSApp.windows.first { $0.canBecomeMain && !($0 is NSPanel) }
    }
}
