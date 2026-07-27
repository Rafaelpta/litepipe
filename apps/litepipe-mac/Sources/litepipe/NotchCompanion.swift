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
    private let engine: EngineController
    private var hoverTimer: Timer?

    init(engine: EngineController) {
        self.engine = engine
    }

    // The window is a FIXED size (the expanded footprint), anchored flush at the
    // top-center, and never resizes. Only the SwiftUI content animates between idle
    // and expanded — so there is no window-resize animation to fight the content
    // spring (that fight was the "green dot mid-screen" / laggy feel).
    private let panelW: CGFloat = 510
    // Taller than the card so the whole card (plus a small buffer) sits inside the
    // collapse rect; otherwise hovering the bottom of the card reads as "outside".
    private let expH: CGFloat = 290

    func show() {
        if let panel { panel.orderFrontRegardless(); return }

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = .clear

        let hosting = NSHostingView(rootView: CompanionView(model: model, engine: engine))
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
        model.expanded = true // the view animates via .animation(value:)
    }

    private func collapse() {
        guard model.expanded else { return }
        panel?.ignoresMouseEvents = true
        model.expanded = false
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
    @ObservedObject var engine: EngineController

    // Accent used for the Upgrade pill (a color, easily re-themed later).
    private let accent = Color(red: 0.29, green: 0.55, blue: 0.98)

    // Recording status label/color derived from the live engine state.
    private var statusLabel: String {
        switch engine.status {
        case .recording: return "Recording"
        case .starting: return "Starting"
        case .paused: return "Paused"
        case .stopped: return "Stopped"
        case .error: return "Error"
        }
    }
    private var statusColor: Color {
        switch engine.status {
        case .recording: return DS.Colors.live
        case .starting: return DS.Colors.faint
        case .paused, .stopped: return DS.Colors.faint
        case .error: return Color(red: 0.90, green: 0.45, blue: 0.40)
        }
    }

    // Real notch geometry from macOS, so the idle bar aligns exactly with the notch
    // and expanded content clears it (no overlap). Falls back if there's no notch.
    private var notch: (w: CGFloat, h: CGFloat) {
        guard let s = NSScreen.screens.first else { return (200, 32) }
        let h = s.safeAreaInsets.top
        var w: CGFloat = 200
        if let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            w = s.frame.width - l.width - r.width
        }
        return (w, h > 0 ? h : 32)
    }

    var body: some View {
        // Both states live in the hierarchy; we crossfade + scale between them so
        // the panel appears to GROW out of the notch (dynamic-island feel) rather
        // than slide down. One spring drives the whole morph.
        ZStack(alignment: .top) {
            expanded
                .opacity(model.expanded ? 1 : 0)
                .scaleEffect(model.expanded ? 1 : 0.55, anchor: .top)
                .allowsHitTesting(model.expanded)
            idle
                .opacity(model.expanded ? 0 : 1)
                .scaleEffect(model.expanded ? 1.4 : 1, anchor: .top)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.6, dampingFraction: 0.82), value: model.expanded)
    }

    // At rest: the notch itself made a bit wider and dropped a little. The bar spans
    // from the very top (screen edge) so its concave top fillets merge into the menu
    // bar (invisible) and only the rounded, scooped bottom shows below the notch.
    // The litepipe wave sits centered in that visible drop.
    private var idle: some View {
        let n = notch
        let ext: CGFloat = 55      // how much wider than the notch, each side
        let drop: CGFloat = 0      // no drop at all: bar stays within the notch height
        return ZStack {
            NotchBarShape(topRadius: 10, bottomRadius: 11).fill(Color.black)
            // Logo beside the notch (a centered logo would sit behind it at this height).
            HStack {
                Spacer()
                WaveShape()
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 18, height: 7)
                    .padding(.trailing, 24)
            }
        }
        .frame(width: n.w + ext * 2, height: n.h + drop)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // Wide two-column landscape panel, faithful to the reference dropdown's layout.
    private var expanded: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notch.h) // sit below the notch line

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
            tab("Timeline", icon: "clock", active: true)
            tab("Search", icon: "magnifyingglass", active: false)
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(statusColor).frame(width: 6, height: 6)
                    .shadow(color: statusColor.opacity(0.7), radius: 3)
                Text(statusLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.Colors.fg)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .contentShape(Capsule())
            .onTapGesture { engine.togglePause() } // pause / resume capture
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

    // MARK: - Left column (timeline + storage)

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Timeline").font(.system(size: 14, weight: .semibold)).foregroundColor(DS.Colors.fg)
                Text("Rewind your screen.").font(.system(size: 11.5)).foregroundColor(DS.Colors.faint)
            }
            RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.06))
                .frame(width: 46, height: 46)
                .overlay(Image(systemName: "clock.arrow.circlepath").font(.system(size: 18)).foregroundColor(DS.Colors.dim))

            Spacer(minLength: 6)

            Text("Storage").font(.system(size: 11, weight: .medium)).foregroundColor(DS.Colors.faint)
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06))
                    .frame(width: 30, height: 30)
                    .overlay(Image(systemName: "folder.fill").font(.system(size: 12)).foregroundColor(DS.Colors.dim))
                    .contentShape(Rectangle())
                    .onTapGesture { engine.openDataFolder() } // open ~/.screenpipe
                RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06))
                    .frame(width: 30, height: 30)
                    .overlay(Image(systemName: "internaldrive.fill").font(.system(size: 12)).foregroundColor(DS.Colors.dim))
                Spacer()
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.03)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Right column (shortcuts + open app)

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 5) {
                Image(systemName: "command").font(.system(size: 10)).foregroundColor(DS.Colors.faint)
                Text("Shortcuts").font(.system(size: 11, weight: .medium)).foregroundColor(DS.Colors.faint)
            }
            shortcut("Timeline", caps: ["⌃", "space"])
            shortcut("Search", caps: ["⌘", "⇧ F"])
            shortcut("Snapshot", caps: ["⌘", "⇧ 4"])
            shortcut("Pause", caps: ["⌃", "⌥ P"])

            Spacer(minLength: 6)

            HStack(spacing: 8) {
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "macwindow").font(.system(size: 9)).foregroundColor(DS.Colors.dim)
                    Text("Open litepipe").font(.system(size: 11.5, weight: .medium)).foregroundColor(DS.Colors.fg)
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

// The macOS notch profile: full-width flat top, small CONCAVE fillets where the
// black meets the light band (the "scoop"), and generously rounded CONVEX bottom
// corners. Used for the idle tab so it reads as an extension of the notch.
struct NotchBarShape: Shape {
    var topRadius: CGFloat = 9
    var bottomRadius: CGFloat = 17
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height, tr = topRadius, br = bottomRadius
        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: tr, y: tr), control: CGPoint(x: tr, y: 0))          // left concave fillet
        p.addLine(to: CGPoint(x: tr, y: h - br))
        p.addQuadCurve(to: CGPoint(x: tr + br, y: h), control: CGPoint(x: tr, y: h))       // bottom-left convex
        p.addLine(to: CGPoint(x: w - tr - br, y: h))
        p.addQuadCurve(to: CGPoint(x: w - tr, y: h - br), control: CGPoint(x: w - tr, y: h)) // bottom-right convex
        p.addLine(to: CGPoint(x: w - tr, y: tr))
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - tr, y: 0))          // right concave fillet
        p.closeSubpath()
        return p
    }
}
