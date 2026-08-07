import AppKit

/// The ⌥⌃ chord that toggles capture from anywhere, replicating the semantics
/// the shipping app uses in the notch companion so muscle memory carries over.
///
/// A quick TAP of the chord toggles on release. Any other key pressed while it
/// is held marks the chord dirty and the release does nothing — window managers
/// and app shortcuts use control+option plus a letter, and those must not pause
/// capture by accident.
@MainActor
final class GlobalHotkey {
    static let shared = GlobalHotkey()

    private var monitor: Any?
    private var localMonitor: Any?
    private var chordActive = false
    private var chordDirty = false
    private var onToggle: (() -> Void)?

    /// True once a monitor is installed. A global monitor silently returns nil
    /// without Accessibility permission, and the caller needs to be able to say
    /// so rather than leave the user pressing a dead shortcut.
    private(set) var installed = false

    func start(onToggle: @escaping () -> Void) {
        guard monitor == nil else { return }
        self.onToggle = onToggle
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] e in
            MainActor.assumeIsolated { self?.handle(e) }
        }
        // The global monitor never sees events aimed at this app, so the chord
        // would be dead while the window is focused without this one.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] e in
            MainActor.assumeIsolated { self?.handle(e) }
            return e
        }
        installed = monitor != nil
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        monitor = nil
        localMonitor = nil
        installed = false
    }

    private func handle(_ e: NSEvent) {
        if e.type == .keyDown {
            if chordActive { chordDirty = true }
            return
        }
        let both = e.modifierFlags.contains(.control) && e.modifierFlags.contains(.option)
        if both, !chordActive {
            chordActive = true
            chordDirty = false
        } else if !both, chordActive {
            chordActive = false
            if !chordDirty { onToggle?() }
        }
    }

    /// Whether the process can install a working global monitor. Without this
    /// the chord only fires while the app is focused, which is worse than
    /// useless for a control meant to work from anywhere.
    static var hasAccessibility: Bool { AXIsProcessTrusted() }
}
