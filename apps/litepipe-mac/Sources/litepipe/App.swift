import AppKit
import SwiftUI

// A non-activating panel that still accepts key input so buttons work.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The app runs a SwiftUI scene for the archive window and an AppKit delegate for
/// everything that came before it: the engine process, the notch companion, the
/// onboarding panel. Neither one owns the other, and the notch is untouched.
@main
struct LitepipeApp: App {
    static let archiveWindowID = "archive"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("litepipe", id: Self.archiveWindowID) {
            ArchiveWindow(engine: delegate.engine)
        }
        .defaultSize(width: 1280, height: 800)
        .commands { ArchiveCommands() }
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
    private var panel: NSPanel?
    private let dragHelper = DragHelperController()
    let engine = EngineController()
    private lazy var companion = NotchCompanionController(engine: engine)

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
            companion.show()
        } else {
            // The archive window is restored by the scene before this runs, and
            // a grid of captures behind the onboarding panel is the wrong first
            // impression. Nothing has been captured yet anyway.
            closeArchiveWindow()
            showOnboarding()
        }

        let nc = NotificationCenter.default
        nc.addObserver(forName: .litepipeClose, object: nil, queue: .main) { [weak self] _ in
            self?.dragHelper.hide()
            self?.panel?.orderOut(nil)
        }
        nc.addObserver(forName: .litepipeShowDragHelper, object: nil, queue: .main) { [weak self] _ in
            self?.dragHelper.show()
        }
        nc.addObserver(forName: .litepipeHideDragHelper, object: nil, queue: .main) { [weak self] _ in
            self?.dragHelper.hide()
        }
        // Keep the onboarding panel pinned under the notch when displays change.
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                       object: nil, queue: .main) { [weak self] _ in
            guard let self, let panel = self.panel, let screen = litepipeNotchScreen() else { return }
            let f = screen.frame
            let x = f.origin.x + (f.width - panel.frame.width) / 2
            panel.setFrameTopLeftPoint(NSPoint(x: x, y: f.origin.y + f.height))
        }
        // Onboarding finished -> tear it down and bring up the persistent companion.
        nc.addObserver(forName: .litepipeOnboardingDone, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.dragHelper.hide()
            self.panel?.orderOut(nil)
            self.panel = nil
            self.engine.start()
            self.companion.show()
        }
    }

    /// The app is a capture engine that happens to have a window, not a document
    /// app. Closing the archive leaves the notch and the engine running, and
    /// under the SwiftUI lifecycle the default is the opposite: the last window
    /// closing takes the whole process with it, silently.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // Without this the posix_spawned engine child outlives the app (holding port
    // 3030 and re-prompting for permissions on the next launch).
    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }

    // Dock click: onboarding first if it is still up, otherwise the archive,
    // falling back to the notch when the window has been closed.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let panel {
            panel.orderFrontRegardless()
        } else if let archive = Self.archiveWindow() {
            archive.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            companion.show()
        }
        return false
    }

    /// The scene's window, picked out of the set the app owns. The notch and the
    /// onboarding panel are NSPanels and never become main, which is what tells
    /// them apart from the document window.
    static func archiveWindow() -> NSWindow? {
        NSApp.windows.first { $0.canBecomeMain && !($0 is NSPanel) }
    }

    private func closeArchiveWindow() {
        Self.archiveWindow()?.close()
    }

    private func showOnboarding() {
        let width = DS.Dim.panelWidth
        let height: CGFloat = 640

        let hosting = NSHostingView(rootView: OnboardingView())
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear

        let panel = NotchPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: 1002) // above the menu bar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting

        // Pin the top edge flush with the physical top, centered under the notch.
        if let screen = litepipeNotchScreen() {
            let f = screen.frame // full frame includes the menu-bar / notch strip
            let x = f.origin.x + (f.width - width) / 2
            let topY = f.origin.y + f.height
            panel.setFrameTopLeftPoint(NSPoint(x: x, y: topY))
        }

        panel.orderFrontRegardless()
        self.panel = panel
    }
}

