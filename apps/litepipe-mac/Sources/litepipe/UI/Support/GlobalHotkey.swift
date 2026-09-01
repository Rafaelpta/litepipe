import AppKit

/// The shortcut that toggles capture from anywhere.
///
/// It fires on the key press itself. The chord this replaces watched the
/// modifiers and toggled when they were released with no other key seen in
/// between, which meant any hand passing through ⌃⌥ on its way to another
/// application's shortcut could pause capture without the user knowing.
@MainActor
final class GlobalHotkey {
    static let shared = GlobalHotkey()

    private var monitor: Any?
    private var localMonitor: Any?
    private var onToggle: (() -> Void)?

    /// True once a monitor is installed. A global monitor silently returns nil
    /// without Accessibility permission, and the caller needs to be able to say
    /// so rather than leave the user pressing a dead shortcut.
    private(set) var installed = false

    func start(onToggle: @escaping () -> Void) {
        guard monitor == nil else { return }
        self.onToggle = onToggle
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] e in
            MainActor.assumeIsolated { _ = self?.handle(e) }
        }
        // The global monitor never sees events aimed at this app, so the shortcut
        // would be dead while litepipe's own window is focused without this one.
        // Swallowing a match here keeps the key from also reaching the UI.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] e in
            let handled = MainActor.assumeIsolated { self?.handle(e) } ?? false
            return handled ? nil : e
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

    /// Pick up a shortcut the user just changed, without disturbing capture.
    func reload() {
        guard let onToggle else { return }
        stop()
        start(onToggle: onToggle)
    }

    @discardableResult
    private func handle(_ e: NSEvent) -> Bool {
        guard let binding = HotkeyBinding.current, binding.matches(e) else { return false }
        onToggle?()
        return true
    }

    /// Whether the process can install a working global monitor. Without this
    /// the shortcut only fires while the app is focused, which is worse than
    /// useless for a control meant to work from anywhere.
    static var hasAccessibility: Bool { AXIsProcessTrusted() }
}
