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

    /// The scale the archive window is drawn on. The notch keeps its black panel,
    /// because it has to merge with the physical notch, but everything inside it
    /// is sized and filled like the window so the two read as one product.
    ///
    /// Fills are the system's `.quaternary` rather than a hand-mixed white
    /// opacity: same token the window uses, and it resolves correctly against the
    /// panel because the panel forces the dark scheme.
    enum Scale {
        static let title: CGFloat = 13
        static let body: CGFloat = 12
        static let caption: CGFloat = 11
        static let footnote: CGFloat = 10.5
        static let control: CGFloat = 7            // pills, buttons, rows
        static let chip: CGFloat = 5               // keycaps, icon tiles
        static let dot: CGFloat = 7                // the capture indicator
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
