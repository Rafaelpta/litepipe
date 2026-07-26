import AppKit
import SwiftUI

// Shared state so the arrow can point toward whichever side the Settings window is.
final class DragHelperModel: ObservableObject {
    @Published var pointsLeft = true // true => System Settings is to our left
}

// A guided floating helper anchored beside the System Settings window: a bar that
// mimics a permission-list row, an arrow pointing at the list, and a reliable
// AppKit file drag that drops litepipe straight into the list — then auto-hides.
final class DragHelperController {
    private var panel: NSPanel?
    private var tracker: Timer?
    private let model = DragHelperModel()
    private let width: CGFloat = 300
    private let height: CGFloat = 96

    func show() {
        guard panel == nil else { return }
        let appURL = Bundle.main.bundleURL

        let hosting = NSHostingView(rootView: DragHelperView(appURL: appURL, model: model))
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
        panel = p

        reposition()
        p.orderFrontRegardless()

        tracker = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            self?.reposition()
        }
    }

    func hide() {
        tracker?.invalidate(); tracker = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func reposition() {
        guard let panel, let screen = NSScreen.screens.first else { return }
        let sf = screen.frame
        let gap: CGFloat = 16

        if let s = SettingsWindowLocator.settingsWindowFrame() {
            var x = s.maxX + gap
            var pointsLeft = true // helper sits right of Settings -> arrow points left
            if x + width > sf.maxX {
                x = s.minX - gap - width
                pointsLeft = false
            }
            x = max(sf.minX + 8, min(x, sf.maxX - width - 8))
            model.pointsLeft = pointsLeft
            let cocoaTopY = sf.height - (s.minY + 56) // near the top of the list
            panel.setFrameTopLeftPoint(NSPoint(x: x, y: max(60, cocoaTopY)))
        } else {
            model.pointsLeft = true
            let x = sf.origin.x + sf.width * 0.60
            let topY = sf.origin.y + sf.height * 0.62
            panel.setFrameTopLeftPoint(NSPoint(x: x, y: topY))
        }
    }
}

struct DragHelperView: View {
    let appURL: URL
    @ObservedObject var model: DragHelperModel
    @State private var nudge = false

    var body: some View {
        VStack(spacing: 8) {
            Text("drag me into the list")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(0.82)))

            HStack(spacing: 8) {
                if model.pointsLeft { arrow(left: true) }
                AppDragBar(appURL: appURL).frame(width: 240, height: 46)
                if !model.pointsLeft { arrow(left: false) }
            }
        }
    }

    private func arrow(left: Bool) -> some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.82)).frame(width: 26, height: 26)
            Image(systemName: left ? "arrow.left" : "arrow.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
        }
        .offset(x: nudge ? (left ? -3 : 3) : 0)
        .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { nudge = true } }
    }
}

// SwiftUI content for the draggable row bar (rendered inside the AppKit source).
struct DragRow: View {
    let appURL: URL
    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                .resizable()
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text("litepipe")
                .font(.system(size: 13.5))
                .foregroundColor(.black.opacity(0.85))
            Spacer(minLength: 12)
            ZStack(alignment: .leading) {
                Capsule().fill(Color(white: 0.80)).frame(width: 30, height: 18)
                Circle().fill(.white).frame(width: 15, height: 15).padding(.leading, 2)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .frame(width: 240)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(white: 0.965)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(.black.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.32), radius: 12, y: 5)
    }
}

// AppKit drag source: a Finder-style file-URL drag that System Settings reliably
// accepts, and which posts a hide once the app is dropped into the list.
struct AppDragBar: NSViewRepresentable {
    let appURL: URL
    func makeNSView(context: Context) -> DragSourceView { DragSourceView(appURL: appURL) }
    func updateNSView(_ nsView: DragSourceView, context: Context) {}
}

final class DragSourceView: NSView, NSDraggingSource {
    let appURL: URL
    private var down: NSPoint?
    private var dragging = false

    init(appURL: URL) {
        self.appURL = appURL
        super.init(frame: .zero)
        let host = NSHostingView(rootView: DragRow(appURL: appURL).allowsHitTesting(false))
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func mouseDown(with event: NSEvent) {
        down = convert(event.locationInWindow, from: nil)
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragging, let d = down else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard hypot(p.x - d.x, p.y - d.y) > 4 else { return }
        dragging = true

        let item = NSDraggingItem(pasteboardWriter: appURL as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 48, height: 48)
        item.setDraggingFrame(NSRect(x: p.x - 24, y: p.y - 24, width: 48, height: 48), contents: icon)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        down = nil; dragging = false
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        down = nil; dragging = false
        if operation != [] { // dropped somewhere (into the Settings list)
            NotificationCenter.default.post(name: .litepipeHideDragHelper, object: nil)
        }
    }
}
