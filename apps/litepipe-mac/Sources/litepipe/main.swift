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
        NSApp.setActivationPolicy(.accessory) // no Dock icon; lives in the notch

        // If onboarding is already complete, start the engine and show the companion.
        if UserDefaults.standard.bool(forKey: "onboarding.complete.v1") {
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
        if let screen = NSScreen.screens.first {
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
