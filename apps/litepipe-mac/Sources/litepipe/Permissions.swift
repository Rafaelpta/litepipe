import AppKit
import AVFoundation
import ApplicationServices
import CoreGraphics
import CoreServices

// Native, honest permission checks. Screen recording uses CGPreflight (a cached
// TCC read that does not false-positive), matching what a production build needs.
enum Permission: String, CaseIterable {
    case screen
    case accessibility
    case microphone
    case browser

    var title: String {
        switch self {
        case .screen: return "I need screen share"
        case .accessibility: return "I need accessibility permissions"
        case .microphone: return "Can I hear you too?"
        case .browser: return "What were you reading?"
        }
    }

    var why: String {
        switch self {
        case .screen:
            return "So I can capture and rewind what you were doing. Recorded only to your Mac."
        case .accessibility:
            return "To turn what's on screen into searchable text. Processed locally."
        case .microphone:
            return "To capture what you say alongside your screen. Skip if you only want screen."
        case .browser:
            return "To read the URL of your active browser tab, so your history knows the page, not just the pixels. Skip if you'd rather not."
        }
    }

    var action: String {
        switch self {
        case .screen: return "Grant screen recording"
        case .accessibility: return "Grant accessibility"
        case .microphone: return "Allow microphone"
        case .browser: return "Allow browser access"
        }
    }

    var skippable: Bool { self == .microphone || self == .browser }

    // Drag-capable permissions get the "drag me into the list" helper.
    var dragHint: Bool { self == .screen || self == .accessibility }

    // Screen Recording only takes effect after the app relaunches (macOS caches
    // CGPreflight at launch), so this step needs a "restart to apply" affordance.
    var needsRestart: Bool { self == .screen }
}

enum Permissions {
    static func isGranted(_ p: Permission) -> Bool {
        switch p {
        case .screen:
            return CGPreflightScreenCaptureAccess()
        case .accessibility:
            return AXIsProcessTrusted()
        case .microphone:
            return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .browser:
            return browserAutomationGranted()
        }
    }

    static func request(_ p: Permission) {
        switch p {
        case .screen:
            // Triggers the native prompt on first ask; opens Settings otherwise.
            if !CGPreflightScreenCaptureAccess() {
                CGRequestScreenCaptureAccess()
            }
            openSettings("Privacy_ScreenCapture")
        case .accessibility:
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
            openSettings("Privacy_Accessibility")
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        case .browser:
            // Poke each running browser so macOS shows the Automation prompt and
            // litepipe appears in the Automation list; then open that pane.
            triggerBrowserAutomationPrompts()
            openSettings("Privacy_Automation")
        }
    }

    private static func openSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    // Relaunch the app so a freshly granted Screen Recording permission takes
    // effect. A detached shell waits for this instance to quit, then reopens it;
    // onboarding resumes (persisted) and now detects the grant.
    static func relaunchApp() {
        let path = Bundle.main.bundlePath
        let p = Process()
        p.launchPath = "/bin/sh"
        p.arguments = ["-c", "sleep 1; open \"\(path)\""]
        try? p.run()
        NSApp.terminate(nil)
    }

    // MARK: - Browser automation (URL capture)

    // Bundle id + AppleScript app name for the browsers we can read a URL from.
    private static let knownBrowsers: [(bundleID: String, appName: String)] = [
        ("com.apple.Safari", "Safari"),
        ("com.google.Chrome", "Google Chrome"),
        ("com.microsoft.edgemac", "Microsoft Edge"),
        ("com.brave.Browser", "Brave Browser"),
        ("company.thebrowser.Browser", "Arc"),
    ]

    // Granted if automation is allowed for at least one browser we support.
    static func browserAutomationGranted() -> Bool {
        knownBrowsers.contains { automationAllowed($0.bundleID) }
    }

    private static func automationAllowed(_ bundleID: String) -> Bool {
        guard let desc = NSAppleEventDescriptor(bundleIdentifier: bundleID).aeDesc else { return false }
        // askUserIfNeeded: false -> just report the current state, never prompt here.
        return AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, false) == noErr
    }

    private static func triggerBrowserAutomationPrompts() {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        for b in knownBrowsers where running.contains(b.bundleID) {
            var err: NSDictionary?
            NSAppleScript(source: "tell application \"\(b.appName)\" to get name of front window")?
                .executeAndReturnError(&err)
        }
    }
}
