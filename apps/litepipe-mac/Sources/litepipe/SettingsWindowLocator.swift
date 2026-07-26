import AppKit
import CoreGraphics

// Finds the System Settings window on screen so the drag helper can anchor to it
// (and follow it as it moves), instead of guessing a fixed position. Uses the
// window server (CGWindowList), which needs no accessibility permission.
enum SettingsWindowLocator {
    private static let settingsBundleID = "com.apple.systempreferences"

    /// The System Settings main window frame, in top-left-origin global coords
    /// (as CGWindowList reports). Returns the largest window owned by the app.
    static func settingsWindowFrame() -> CGRect? {
        let running = NSWorkspace.shared.runningApplications
        guard let app = running.first(where: { $0.bundleIdentifier == settingsBundleID }) else { return nil }
        let pid = app.processIdentifier

        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        var best: CGRect?
        var bestArea: CGFloat = 0
        for info in list {
            guard let owner = info[kCGWindowOwnerPID as String] as? pid_t, owner == pid else { continue }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let b = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let rect = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            let area = rect.width * rect.height
            if area > bestArea { bestArea = area; best = rect }
        }
        return best
    }
}
