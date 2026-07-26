import SwiftUI

// Ottic palette + panel dimensions. Original values (warm-stone on black),
// reconstructed from our own reference measurements — no third-party assets.
enum DS {
    enum Colors {
        static let panel = Color.black
        static let fg = Color(hex: 0xF2F4F2)      // warm near-white
        static let dim = Color(hex: 0x9AA0A0)     // subtitle gray
        static let faint = Color(hex: 0x6B706E)   // muted
        static let hair = Color.white.opacity(0.10)
        static let btn = Color(hex: 0xF2F2F2)      // off-white pill
        static let btnInk = Color(hex: 0x141414)
        static let live = Color(hex: 0x34D399)     // success green (semantic only)
    }

    enum Dim {
        static let panelWidth: CGFloat = 460
        static let panelRadius: CGFloat = 22       // bottom corners only (hangs from notch)
    }

    enum Motion {
        static let fast: Double = 0.15
        static let normal: Double = 0.25
        static let slow: Double = 0.4
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}

// Primary pill button. Reproduces the motion feel: hover swells the button to
// 1.03 over ~0.6s with a glow that gently breathes on a 2.5s loop; press snaps
// to 0.97 in 0.1s. Implemented as original SwiftUI (no third-party code/assets).
struct PillButtonStyle: ButtonStyle {
    var bg: Color = DS.Colors.btn
    var fg: Color = DS.Colors.btnInk

    func makeBody(configuration: Configuration) -> some View { PillBody(configuration: configuration, bg: bg, fg: fg) }

    struct PillBody: View {
        let configuration: Configuration
        let bg: Color
        let fg: Color
        @State private var hovering = false
        @State private var breathing = false

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(fg)
                .padding(.vertical, 9)
                .padding(.horizontal, 26)
                .background(Capsule().fill(bg))
                .scaleEffect(configuration.isPressed ? 0.97 : (hovering ? 1.03 : 1.0))
                .shadow(color: bg.opacity(hovering ? (breathing ? 0.34 : 0.18) : 0),
                        radius: hovering ? (breathing ? 16 : 10) : 0)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
                .onHover { h in
                    withAnimation(.easeInOut(duration: h ? 0.6 : 0.3)) { hovering = h }
                    if h {
                        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) { breathing = true }
                    } else {
                        withAnimation(.easeOut(duration: 0.3)) { breathing = false }
                    }
                    if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
        }
    }
}

// Panel shape: flat top edge (flush with the notch), rounded bottom corners.
struct HangShape: Shape {
    var radius: CGFloat = DS.Dim.panelRadius
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        p.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
            radius: radius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        p.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
            radius: radius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.closeSubpath()
        return p
    }
}
