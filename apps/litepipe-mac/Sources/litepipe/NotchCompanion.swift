import AppKit
import SwiftUI
import Combine

// Dynamic-notch companion: at rest, a tiny non-intrusive indicator hugs the notch;
// hovering the notch expands a wide two-column panel that wraps below it, collapsing
// when the pointer leaves. Original SwiftUI reimplementation of the reference
// dropdown's layout/proportions in litepipe's palette (neutral placeholder copy in
// the name/marketing slots).
final class CompanionModel: ObservableObject {
    @Published var expanded = false
}

final class NotchCompanionController {
    private var panel: NSPanel?
    private let model = CompanionModel()
    private var hoverTimer: Timer?

    // The window is a FIXED size (the expanded footprint), anchored flush at the
    // top-center, and never resizes. Only the SwiftUI content animates between idle
    // and expanded — so there is no window-resize animation to fight the content
    // spring (that fight was the "green dot mid-screen" / laggy feel).
    private let panelW: CGFloat = 510
    private let expH: CGFloat = 244

    func show() {
        if let panel { panel.orderFrontRegardless(); return }

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = .clear

        let hosting = NSHostingView(rootView: CompanionView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelW, height: expH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        p.isFloatingPanel = true
        p.level = NSWindow.Level(rawValue: 1002)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.acceptsMouseMovedEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = container
        p.ignoresMouseEvents = true // idle: transparent area passes clicks through
        panel = p

        if let r = expandedRect() { p.setFrame(r, display: false) }
        p.orderFrontRegardless()
        startHoverTracking()
    }

    func hide() {
        hoverTimer?.invalidate(); hoverTimer = nil
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Hover tracking

    // Poll the cursor position against computed rects. `NSEvent.mouseLocation` is a
    // queryable global property (independent of event *delivery*, which is why this
    // is reliable for an accessory / non-activating app where `.mouseMoved` monitors
    // and NSTrackingArea on a resizing panel are not). Fluidity comes from the spring
    // animation, not the sampling rate. This is the pattern notch dropdowns use.
    private func startHoverTracking() {
        hoverTimer?.invalidate()
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.handleMouse() }
        RunLoop.main.add(t, forMode: .common) // keep firing during menu/tracking runloop modes
        hoverTimer = t
    }

    private func handleMouse() {
        let loc = NSEvent.mouseLocation
        if model.expanded {
            if let r = expandedRect(), !r.insetBy(dx: -10, dy: -10).contains(loc) { collapse() }
        } else {
            if let r = triggerRect(), r.contains(loc) { expand() }
        }
    }

    private func expand() {
        guard !model.expanded else { return }
        panel?.ignoresMouseEvents = false // become interactive while open
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { model.expanded = true }
    }

    private func collapse() {
        guard model.expanded else { return }
        panel?.ignoresMouseEvents = true
        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) { model.expanded = false }
    }

    // Narrow trigger zone hugging the notch (so it only expands when you approach
    // the notch, not anywhere across the top of the screen).
    private func triggerRect() -> NSRect? {
        guard let screen = NSScreen.screens.first else { return nil }
        let f = screen.frame
        let w: CGFloat = 230, h: CGFloat = 40
        let x = f.origin.x + (f.width - w) / 2
        return NSRect(x: x, y: f.origin.y + f.height - h, width: w, height: h)
    }

    private func expandedRect() -> NSRect? {
        guard let screen = NSScreen.screens.first else { return nil }
        let f = screen.frame
        let x = f.origin.x + (f.width - panelW) / 2
        return NSRect(x: x, y: f.origin.y + f.height - expH, width: panelW, height: expH)
    }
}

struct CompanionView: View {
    @ObservedObject var model: CompanionModel

    // Accent used for the Upgrade pill (a color, easily re-themed later).
    private let accent = Color(red: 0.29, green: 0.55, blue: 0.98)

    var body: some View {
        ZStack(alignment: .top) {
            if model.expanded {
                expanded.transition(.move(edge: .top).combined(with: .opacity))
            } else {
                idle.transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // At rest: a subtle recording dot tucked just under the notch (pinned to the
    // TOP so it hugs the notch, not the bottom of the fixed window).
    private var idle: some View {
        Circle()
            .fill(DS.Colors.live)
            .frame(width: 6, height: 6)
            .shadow(color: DS.Colors.live.opacity(0.7), radius: 3)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 30)
    }

    // Wide two-column landscape panel, faithful to the reference dropdown's layout.
    private var expanded: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 30) // sit below the notch line

            topBar
                .padding(.horizontal, 14)
                .padding(.bottom, 14)

            HStack(alignment: .top, spacing: 22) {
                leftColumn
                rightColumn
            }
            .padding(.horizontal, 16)

            Color.clear.frame(height: 14)
        }
        .frame(width: 510, alignment: .top)
        .background(DS.Colors.panel)
        .clipShape(HangShape(radius: 20))
        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 6) {
            tab("Home", icon: "house.fill", active: true)
            tab("Agents", icon: "sparkles", active: false)
            Spacer()
            Text("Upgrade to Pro")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(Capsule().fill(accent))
            Image(systemName: "gearshape.fill")
                .font(.system(size: 13))
                .foregroundColor(DS.Colors.faint)
                .padding(.leading, 2)
        }
    }

    private func tab(_ title: String, icon: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10))
            Text(title).font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(active ? DS.Colors.fg : DS.Colors.faint)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(active ? Color.white.opacity(0.10) : .clear))
    }

    // MARK: - Left column (skills + integrations)

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add skills").font(.system(size: 14, weight: .semibold)).foregroundColor(DS.Colors.fg)
                Text("Extend what it can do.").font(.system(size: 11.5)).foregroundColor(DS.Colors.faint)
            }
            RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.06))
                .frame(width: 46, height: 46)
                .overlay(Image(systemName: "plus").font(.system(size: 17, weight: .medium)).foregroundColor(DS.Colors.dim))

            Spacer(minLength: 6)

            Text("Active integrations").font(.system(size: 11, weight: .medium)).foregroundColor(DS.Colors.faint)
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06))
                    .frame(width: 30, height: 30)
                    .overlay(Image(systemName: "envelope.fill").font(.system(size: 12)).foregroundColor(DS.Colors.dim))
                RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06))
                    .frame(width: 30, height: 30)
                    .overlay(Image(systemName: "plus").font(.system(size: 12, weight: .medium)).foregroundColor(DS.Colors.faint))
                Spacer()
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.03)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Right column (shortcuts + undock)

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 5) {
                Image(systemName: "command").font(.system(size: 10)).foregroundColor(DS.Colors.faint)
                Text("Shortcuts").font(.system(size: 11, weight: .medium)).foregroundColor(DS.Colors.faint)
            }
            shortcut("Talk", caps: ["⌃ control", "⌥ option"])
            shortcut("Text", caps: ["⌃ control", "2×"])
            shortcut("Dictate", caps: ["fn", "⌃ control"])
            shortcut("Hands-free", caps: ["fn", "⌃ control", "2×"])

            Spacer(minLength: 6)

            HStack(spacing: 8) {
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "play.fill").font(.system(size: 8)).foregroundColor(DS.Colors.live)
                    Text("Undock Cursor").font(.system(size: 11.5, weight: .medium)).foregroundColor(DS.Colors.fg)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))

                Circle().fill(Color.white.opacity(0.06)).frame(width: 26, height: 26)
                    .overlay(Image(systemName: "info").font(.system(size: 10, weight: .semibold)).foregroundColor(DS.Colors.faint))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shortcut(_ label: String, caps: [String]) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.system(size: 12)).foregroundColor(DS.Colors.dim)
            Spacer(minLength: 6)
            ForEach(caps.indices, id: \.self) { i in keycap(caps[i]) }
        }
    }

    private func keycap(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(DS.Colors.dim)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)))
    }
}
