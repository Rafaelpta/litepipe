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

// The screen that physically has the notch (safeAreaInsets.top > 0), so the
// companion lands on it even with multiple monitors. Falls back sensibly.
func litepipeNotchScreen() -> NSScreen? {
    for s in NSScreen.screens where s.safeAreaInsets.top > 0 { return s }
    return NSScreen.main ?? NSScreen.screens.last
}

final class NotchCompanionController {
    private var panel: NSPanel?
    private let model = CompanionModel()
    private let engine: EngineController
    private lazy var timeline = TimelineController(dataDir: engine.dataFolder)
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
    private let expH: CGFloat = 250

    func show() {
        if let panel { panel.orderFrontRegardless(); return }

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = .clear

        let hosting = NSHostingView(rootView: CompanionView(
            model: model,
            engine: engine,
            onOpenTimeline: { [weak self] in self?.timeline.show() }
        ))
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
        guard let screen = litepipeNotchScreen() else { return nil }
        let f = screen.frame
        let w: CGFloat = 230, h: CGFloat = 40
        let x = f.origin.x + (f.width - w) / 2
        return NSRect(x: x, y: f.origin.y + f.height - h, width: w, height: h)
    }

    private func expandedRect() -> NSRect? {
        guard let screen = litepipeNotchScreen() else { return nil }
        let f = screen.frame
        let x = f.origin.x + (f.width - panelW) / 2
        return NSRect(x: x, y: f.origin.y + f.height - expH, width: panelW, height: expH)
    }
}

struct CompanionView: View {
    @ObservedObject var model: CompanionModel
    @ObservedObject var engine: EngineController
    let onOpenTimeline: () -> Void

    // Accent used for the Upgrade pill (a color, easily re-themed later).
    private let accent = Color(red: 0.29, green: 0.55, blue: 0.98)

    // Status label/color derived from the live engine state. "Context awareness"
    // reads gentler than "recording".
    private var statusLabel: String {
        switch engine.status {
        case .recording: return "Context awareness"
        case .starting: return "Starting"
        case .paused: return "Paused"
        case .stopped: return "Off"
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
        guard let s = litepipeNotchScreen() else { return (200, 32) }
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
        HStack(spacing: 8) {
            WaveShape()
                .stroke(DS.Colors.fg, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .frame(width: 20, height: 10)
            Text("litepipe").font(.system(size: 14, weight: .semibold)).foregroundColor(DS.Colors.fg)
            Text("Local memory of your work").font(.system(size: 11)).foregroundColor(DS.Colors.faint)
            Spacer()
        }
    }

    // MARK: - Left column (context awareness + pause/resume)

    private var leftColumn: some View {
        ContextControl(engine: engine)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Right column (actions)

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 9) {
            ActionRow(icon: "clock.arrow.circlepath", label: "Open timeline", trailing: "arrow.up.right") { onOpenTimeline() }
            ActionRow(icon: "folder", label: "Open data folder", trailing: "arrow.up.right") { engine.openDataFolder() }
            ActionRow(icon: "gearshape", label: "Settings", trailing: "chevron.right") { /* TODO: settings */ }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Context awareness status + pause/resume. Green dot when on; a big, plain button
// toggles Pause / Resume; the ⌥⌃ shortcut is shown beneath.
private struct ContextControl: View {
    @ObservedObject var engine: EngineController
    @State private var hover = false

    var body: some View {
        let paused = engine.status == .paused
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 6) {
                Circle().fill(paused ? DS.Colors.faint : DS.Colors.live)
                    .frame(width: 7, height: 7)
                    .shadow(color: (paused ? Color.clear : DS.Colors.live).opacity(0.7), radius: 3)
                Text("Context aware").font(.system(size: 14, weight: .semibold)).foregroundColor(DS.Colors.fg)
                if paused {
                    Text("· paused").font(.system(size: 11)).foregroundColor(DS.Colors.faint)
                }
            }

            Button(action: { engine.togglePause() }) {
                HStack(spacing: 7) {
                    Image(systemName: paused ? "play.fill" : "pause.fill").font(.system(size: 12, weight: .semibold))
                    Text(paused ? "Resume" : "Pause").font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(paused ? DS.Colors.live : DS.Colors.fg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(hover ? 0.13 : 0.07)))
                .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    Image(systemName: "command").font(.system(size: 10)).foregroundColor(DS.Colors.faint)
                    Text("Shortcuts").font(.system(size: 11, weight: .medium)).foregroundColor(DS.Colors.faint)
                }
                HStack(spacing: 6) {
                    Text("Pause / resume").font(.system(size: 12)).foregroundColor(DS.Colors.dim)
                    Spacer(minLength: 6)
                    keycap("⌥"); keycap("⌃")
                }
            }
        }
    }

    private func keycap(_ s: String) -> some View {
        Text(s).font(.system(size: 10, weight: .medium)).foregroundColor(DS.Colors.dim)
            .frame(minWidth: 18).padding(.horizontal, 5).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)))
    }
}

// A full-width action button with a leading icon and a hover highlight.
private struct ActionRow: View {
    let icon: String
    let label: String
    var trailing: String = "chevron.right"
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 13)).foregroundColor(DS.Colors.dim).frame(width: 18)
                Text(label).font(.system(size: 12.5, weight: .medium)).foregroundColor(DS.Colors.fg)
                Spacer()
                Image(systemName: trailing).font(.system(size: 10, weight: .semibold)).foregroundColor(DS.Colors.faint)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(hover ? 0.11 : 0.05)))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
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
