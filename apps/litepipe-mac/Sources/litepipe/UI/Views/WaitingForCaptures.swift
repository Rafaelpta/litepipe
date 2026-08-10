import SwiftUI
import AppKit

/// The first thing a new install shows, and for a minute or two the only thing.
///
/// An empty archive used to read "No Captures · Nothing captured for this filter
/// yet", which describes a filter that found nothing rather than a product that
/// has just started working. Someone who installed litepipe thirty seconds ago
/// cannot tell that apart from a broken install, so they sit and wait at a page
/// that gives them no reason to believe anything is coming.
///
/// This says the three things they actually need: that capture is running, what
/// makes a moment appear, and roughly when to expect one. The clock ticks and
/// the rings breathe because a still page is the thing that reads as stuck.
struct WaitingForCaptures: View {
    @Environment(NavigationState.self) private var nav
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let screenRecordingSettings =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"

    private var trouble: String? { nav.engineTrouble }
    private var paused: Bool { nav.capturePaused }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            Pulse(active: !paused && trouble == nil && !reduceMotion)
                .frame(width: 132, height: 132)

            VStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                Text(body_)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2.5)
                    .frame(maxWidth: 380)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 22)

            if paused || trouble != nil {
                Button(paused && trouble == nil ? "Resume Context Awareness" : "Open Settings") {
                    if paused && trouble == nil { nav.resumeCapture() }
                    // Reached by URL rather than through Permissions, which this
                    // file cannot see: the prototype target compiles UI/ alone.
                    else if let url = URL(string: Self.screenRecordingSettings) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.large)
                .padding(.top, 18)
            } else {
                watchingLine.padding(.top, 18)
            }

            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, minHeight: 500)
    }

    // MARK: Copy

    /// Present tense. The page is blank, and a title that agrees with the blank
    /// describes the wrong thing: the machine is working, right now.
    private var title: String {
        if trouble != nil { return "Context awareness is not running" }
        if paused { return "Context awareness is paused" }
        return "litepipe is running"
    }

    private var body_: String {
        if let trouble {
            return "\(trouble.prefix(1).capitalized + trouble.dropFirst()). "
                 + "Nothing reaches the archive until that is fixed."
        }
        if paused {
            return "Nothing is recorded while it is off."
        }
        // Nobody should sit here reading. The one instruction is to leave.
        return "Your work starts showing up here within minutes. Go and use your Mac."
    }

    /// The same words the sidebar pill uses, so this reads as the state of the
    /// product rather than a message written for the empty page.
    private var watchingLine: some View {
        HStack(spacing: 7) {
            BlinkingDot()
            Text("Context awareness enabled")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.5), in: Capsule())
    }
}

/// A heartbeat, not a blink: it fades rather than switching off, because a hard
/// on/off in the corner of a still page reads as a warning light.
private struct BlinkingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 6, height: 6)
            .opacity(dim ? 0.25 : 1)
            .animation(reduceMotion ? .default
                       : .easeInOut(duration: 0.85).repeatForever(autoreverses: true),
                       value: dim)
            .onAppear { if !reduceMotion { dim = true } }
    }
}

/// Rings leaving a screen, one after another. Drawn rather than an SF Symbol so
/// it carries the same flat two-tone hand as the unbuilt pages, and so the
/// rhythm can be slow: this sits in front of someone for minutes, and a fast
/// pulse in an idle window reads as urgency.
private struct Pulse: View {
    let active: Bool
    @State private var running = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(Color.accentColor.opacity(0.45), lineWidth: 1.5)
                    .scaleEffect(running ? 1.0 : 0.34)
                    .opacity(running ? 0 : 0.9)
                    .animation(active
                               ? .easeOut(duration: 3).repeatForever(autoreverses: false)
                                   .delay(Double(i))
                               : .default,
                               value: running)
            }

            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.secondary.opacity(0.8), lineWidth: 1.5)
                .frame(width: 40, height: 28)
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.8))
                        .frame(width: 16, height: 2)
                        .offset(y: 5)
                }
                .opacity(active ? 1 : 0.45)
        }
        .onAppear { if active { running = true } }
        .onChange(of: active) { _, on in running = on }
    }
}
