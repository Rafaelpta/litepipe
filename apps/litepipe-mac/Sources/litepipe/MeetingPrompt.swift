import AppKit
import Combine
import SwiftUI

// Floating dark banner under the notch asking to transcribe a detected meeting:
// litepipe icon beside the meeting app's icon, No / Yes actions, and a row of
// capability chips. Shown while MeetingWatcher.suspected is true.
final class MeetingPromptController {
    private var panel: NSPanel?
    private let watcher: MeetingWatcher
    private var subs: Set<AnyCancellable> = []

    init(watcher: MeetingWatcher) {
        self.watcher = watcher
        watcher.$suspected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in on ? self?.show() : self?.hide() }
            .store(in: &subs)
    }

    private func show() {
        guard panel == nil else { panel?.orderFrontRegardless(); return }
        let width: CGFloat = 660, height: CGFloat = 118

        let hosting = NSHostingView(rootView: MeetingPromptView(watcher: watcher))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        p.isFloatingPanel = true
        p.level = NSWindow.Level(rawValue: 1002)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = hosting

        if let screen = litepipeNotchScreen() {
            let f = screen.frame
            let x = f.origin.x + (f.width - width) / 2
            let topY = f.origin.y + f.height - screen.safeAreaInsets.top - 8
            p.setFrameTopLeftPoint(NSPoint(x: x, y: topY))
        }
        p.orderFrontRegardless()
        panel = p
    }

    private func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

struct MeetingPromptView: View {
    @ObservedObject var watcher: MeetingWatcher

    private let blue = Color(red: 0.20, green: 0.45, blue: 0.95)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    icon(NSApp.applicationIconImage)
                    icon(watcher.suspectedAppIcon)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Transcribe this \(watcher.suspectedServiceName ?? "") meeting?"
                        .replacingOccurrences(of: "  ", with: " "))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text("You can use litepipe to:")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.55))
                }
                Spacer(minLength: 12)
                pill(label: "No", icon: "xmark", fill: Color.white.opacity(0.12)) {
                    watcher.decline()
                }
                pill(label: "Yes", icon: "waveform", fill: blue) {
                    watcher.accept()
                }
            }
            HStack(spacing: 8) {
                chip("Transcribe meeting")
                chip("Take notes")
                chip("Summarize a meeting")
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.black.opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 22, y: 10)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func icon(_ image: NSImage?) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    private func pill(label: String, icon: String, fill: Color,
                      _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
                Text(label).font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func chip(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.10)))
    }
}
