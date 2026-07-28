import AppKit
import SwiftUI

// A non-activating panel that still accepts key input so buttons work.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?
    private let dragHelper = DragHelperController()
    private let engine = EngineController()
    private lazy var companion = NotchCompanionController(engine: engine)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular) // Dock icon so the app is visible and quittable

        // Never trust the sticky "complete" flag alone: permissions can be revoked
        // or reset after onboarding finished. Capture only runs with live grants.
        if UserDefaults.standard.bool(forKey: "onboarding.complete.v1"),
           Permissions.allRequiredGranted() {
            engine.start()
            companion.show()
        } else {
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

    // Without this the posix_spawned engine child outlives the app (holding port
    // 3030 and re-prompting for permissions on the next launch).
    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }

    // Dock click: re-front whichever panel is active (a .regular app with no
    // standard windows would otherwise do nothing visible).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let panel {
            panel.orderFrontRegardless()
        } else {
            companion.show()
        }
        return false
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
