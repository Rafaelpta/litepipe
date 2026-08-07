import SwiftUI
import AppKit

/// The litepipe mark — the two-hump squiggle the shipping app draws in
/// onboarding and in the notch. Same control points, so the prototype and the
/// app are the same logo rather than two drawings of the same idea.
struct LitepipeMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let midY = r.midY
        p.move(to: CGPoint(x: r.minX, y: midY))
        p.addCurve(to: CGPoint(x: r.midX, y: midY),
                   control1: CGPoint(x: r.width * 0.22, y: r.minY),
                   control2: CGPoint(x: r.width * 0.28, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.maxX, y: midY),
                   control1: CGPoint(x: r.width * 0.72, y: r.minY),
                   control2: CGPoint(x: r.width * 0.78, y: r.maxY))
        return p
    }
}

enum MenuBarIcon {
    /// Rendered once and marked as a template, so macOS tints it for the light
    /// or dark menu bar and for the highlighted state — which a SwiftUI shape
    /// placed straight into MenuBarExtra does not get.
    @MainActor
    static func image(paused: Bool) -> NSImage {
        if let cached = cache[paused] { return cached }
        let size = CGSize(width: 20, height: 16)
        let renderer = ImageRenderer(content: mark(paused: paused, size: size))
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 3
        let img = renderer.nsImage ?? NSImage(size: size)
        img.isTemplate = true
        cache[paused] = img
        return img
    }

    @MainActor private static var cache: [Bool: NSImage] = [:]

    private static func mark(paused: Bool, size: CGSize) -> some View {
        ZStack {
            LitepipeMark()
                .stroke(Color.black, style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                .padding(.horizontal, 1.5)
                .padding(.vertical, 3.5)
                .opacity(paused ? 0.45 : 1)
            if paused {
                // A slash through the mark, the way a muted glyph reads.
                Path { p in
                    p.move(to: CGPoint(x: size.width * 0.16, y: size.height * 0.85))
                    p.addLine(to: CGPoint(x: size.width * 0.84, y: size.height * 0.15))
                }
                .stroke(Color.black, style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
