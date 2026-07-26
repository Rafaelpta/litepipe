import AppKit
import AVFoundation
import ApplicationServices
import CoreGraphics

// Native, honest permission checks. Screen recording uses CGPreflight (a cached
// TCC read that does not false-positive), matching what a production build needs.
enum Permission: String, CaseIterable {
    case screen
    case accessibility
    case microphone

    var title: String {
        switch self {
        case .screen: return "Let me see your screen."
        case .accessibility: return "Let me read the screen."
        case .microphone: return "Can I hear you too?"
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
        }
    }

    var action: String {
        switch self {
        case .screen: return "Open Screen Recording settings"
        case .accessibility: return "Open Accessibility settings"
        case .microphone: return "Allow microphone"
        }
    }

    var skippable: Bool { self == .microphone }

    // Drag-capable permissions get the "drag me into the list" helper.
    var dragHint: Bool { self == .screen || self == .accessibility }
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
        }
    }

    private static func openSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
