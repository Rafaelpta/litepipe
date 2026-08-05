import SwiftUI
import AppKit

// MARK: - Deterministic fake photo artwork

private struct TriangleShape: Shape {
    var apexX: CGFloat // 0...1
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + apexX * r.width, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct ArtworkView: View {
    let kind: PhotoKind
    let size: CGSize
    private let r: [CGFloat]

    init(seed: UInt64, kind: PhotoKind, size: CGSize) {
        self.kind = kind
        self.size = size
        var g = SplitMix64(seed: seed)
        r = (0..<40).map { _ in CGFloat(Double.random(in: 0...1, using: &g)) }
    }

    private var w: CGFloat { size.width }
    private var h: CGFloat { size.height }

    var body: some View {
        ZStack {
            scene
            // Vignette + slight exposure variation so thumbnails don't look flat
            RadialGradient(colors: [.clear, .black.opacity(0.16 + 0.08 * r[1])],
                           center: .center, startRadius: min(w, h) * 0.45, endRadius: max(w, h) * 0.85)
            Color.black.opacity((r[2] - 0.5) * 0.08)
        }
        .frame(width: w, height: h)
        .clipped()
    }

    @ViewBuilder private var scene: some View {
        switch kind {
        case .landscape: landscape
        case .sunset: sunset
        case .beach: beach
        case .forest: forest
        case .city: city
        case .portrait: portrait
        case .pet: pet
        case .food: food
        case .screenshot: screenshot
        }
    }

    private var landscape: some View {
        ZStack {
            LinearGradient(colors: [Color(hue: 0.58 + 0.03 * r[3], saturation: 0.55, brightness: 0.95),
                                    Color(hue: 0.56, saturation: 0.25, brightness: 1.0)],
                           startPoint: .top, endPoint: .bottom)
            Circle().fill(Color(hue: 0.13, saturation: 0.35, brightness: 1.0))
                .frame(width: w * 0.16)
                .position(x: w * (0.2 + 0.6 * r[4]), y: h * (0.12 + 0.15 * r[5]))
                .blur(radius: w * 0.02)
            TriangleShape(apexX: 0.3 + 0.3 * r[6])
                .fill(Color(hue: 0.6, saturation: 0.32, brightness: 0.45 + 0.1 * r[7]))
                .frame(width: w * 0.9, height: h * 0.42)
                .position(x: w * 0.32, y: h * 0.58)
                .blur(radius: 1.5)
            TriangleShape(apexX: 0.4 + 0.3 * r[8])
                .fill(Color(hue: 0.61, saturation: 0.3, brightness: 0.32))
                .frame(width: w * 1.1, height: h * 0.36)
                .position(x: w * 0.75, y: h * 0.66)
                .blur(radius: 1.5)
            LinearGradient(colors: [Color(hue: 0.3 + 0.05 * r[9], saturation: 0.5, brightness: 0.55),
                                    Color(hue: 0.28, saturation: 0.55, brightness: 0.35)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: h * 0.3)
                .position(x: w / 2, y: h * 0.87)
                .blur(radius: 1)
        }
    }

    private var sunset: some View {
        ZStack {
            LinearGradient(colors: [Color(hue: 0.72, saturation: 0.45, brightness: 0.45),
                                    Color(hue: 0.05 + 0.03 * r[3], saturation: 0.75, brightness: 0.95),
                                    Color(hue: 0.1, saturation: 0.8, brightness: 1.0)],
                           startPoint: .top, endPoint: .bottom)
            Circle().fill(Color(hue: 0.09, saturation: 0.55, brightness: 1.0))
                .frame(width: w * (0.18 + 0.1 * r[4]))
                .position(x: w * (0.25 + 0.5 * r[5]), y: h * 0.62)
                .blur(radius: w * 0.015)
            Rectangle().fill(Color(hue: 0.75, saturation: 0.4, brightness: 0.12))
                .frame(height: h * 0.24)
                .position(x: w / 2, y: h * 0.9)
                .blur(radius: 0.8)
        }
    }

    private var beach: some View {
        ZStack {
            LinearGradient(colors: [Color(hue: 0.56, saturation: 0.5, brightness: 0.98),
                                    Color(hue: 0.54, saturation: 0.2, brightness: 1.0)],
                           startPoint: .top, endPoint: .bottom)
            Rectangle().fill(LinearGradient(colors: [Color(hue: 0.5, saturation: 0.65, brightness: 0.75),
                                                     Color(hue: 0.48, saturation: 0.5, brightness: 0.85)],
                                            startPoint: .top, endPoint: .bottom))
                .frame(height: h * 0.28)
                .position(x: w / 2, y: h * 0.6)
            Rectangle().fill(Color(hue: 0.11, saturation: 0.25, brightness: 0.92))
                .frame(height: h * 0.28)
                .position(x: w / 2, y: h * 0.88)
                .blur(radius: 0.5)
            Circle().fill(.white.opacity(0.9))
                .frame(width: w * 0.1)
                .position(x: w * (0.15 + 0.6 * r[4]), y: h * 0.14)
                .blur(radius: w * 0.02)
        }
    }

    private var forest: some View {
        ZStack {
            LinearGradient(colors: [Color(hue: 0.32, saturation: 0.55, brightness: 0.55),
                                    Color(hue: 0.3, saturation: 0.65, brightness: 0.25)],
                           startPoint: .top, endPoint: .bottom)
            ForEach(0..<6, id: \.self) { i in
                Capsule().fill(Color(hue: 0.31, saturation: 0.5, brightness: 0.12 + 0.08 * r[10 + i]))
                    .frame(width: w * (0.03 + 0.02 * r[16 + i]), height: h * 1.1)
                    .position(x: w * (0.05 + 0.95 * r[22 + i]), y: h * 0.55)
                    .blur(radius: 1)
            }
            Capsule().fill(.white.opacity(0.18))
                .frame(width: w * 0.16, height: h * 1.3)
                .rotationEffect(.degrees(18))
                .position(x: w * (0.3 + 0.4 * r[9]), y: h * 0.4)
                .blur(radius: w * 0.04)
        }
    }

    private var city: some View {
        ZStack {
            LinearGradient(colors: [Color(hue: 0.62, saturation: 0.4, brightness: 0.75),
                                    Color(hue: 0.08, saturation: 0.35, brightness: 0.85)],
                           startPoint: .top, endPoint: .bottom)
            ForEach(0..<8, id: \.self) { i in
                let bh = h * (0.25 + 0.45 * r[10 + i])
                Rectangle().fill(Color(hue: 0.64, saturation: 0.3, brightness: 0.2 + 0.12 * r[18 + i]))
                    .frame(width: w * (0.08 + 0.06 * r[26 + i]), height: bh)
                    .position(x: w * CGFloat(i) / 7.2 + w * 0.04, y: h - bh / 2)
                    .blur(radius: 0.5)
            }
        }
    }

    private var portrait: some View {
        ZStack {
            LinearGradient(colors: [Color(hue: 0.08 + 0.06 * r[3], saturation: 0.35, brightness: 0.85),
                                    Color(hue: 0.07, saturation: 0.45, brightness: 0.6)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(.white.opacity(0.25))
                    .frame(width: w * (0.1 + 0.12 * r[10 + i]))
                    .position(x: w * r[14 + i], y: h * 0.35 * r[18 + i])
                    .blur(radius: w * 0.03)
            }
            // Head + shoulders silhouette
            Circle().fill(Color(hue: 0.07, saturation: 0.5, brightness: 0.25))
                .frame(width: w * 0.34)
                .position(x: w * (0.42 + 0.16 * r[5]), y: h * 0.42)
                .blur(radius: 2)
            Ellipse().fill(Color(hue: 0.65, saturation: 0.35, brightness: 0.22))
                .frame(width: w * 0.72, height: h * 0.5)
                .position(x: w * (0.42 + 0.16 * r[5]), y: h * 0.95)
                .blur(radius: 2)
        }
    }

    private var pet: some View {
        ZStack {
            LinearGradient(colors: [Color(hue: 0.09, saturation: 0.15, brightness: 0.8),
                                    Color(hue: 0.08, saturation: 0.25, brightness: 0.55)],
                           startPoint: .top, endPoint: .bottom)
            let bodyHue = 0.07 + 0.04 * r[3]
            Ellipse().fill(Color(hue: bodyHue, saturation: 0.55, brightness: 0.4 + 0.25 * r[4]))
                .frame(width: w * 0.62, height: h * 0.4)
                .position(x: w * 0.5, y: h * 0.68)
                .blur(radius: 2.5)
            Circle().fill(Color(hue: bodyHue, saturation: 0.55, brightness: 0.45 + 0.25 * r[4]))
                .frame(width: w * 0.3)
                .position(x: w * (0.32 + 0.3 * r[5]), y: h * 0.42)
                .blur(radius: 2)
            TriangleShape(apexX: 0.5).fill(Color(hue: bodyHue, saturation: 0.6, brightness: 0.35))
                .frame(width: w * 0.1, height: h * 0.1)
                .position(x: w * (0.26 + 0.3 * r[5]), y: h * 0.3)
                .blur(radius: 1.5)
            TriangleShape(apexX: 0.5).fill(Color(hue: bodyHue, saturation: 0.6, brightness: 0.35))
                .frame(width: w * 0.1, height: h * 0.1)
                .position(x: w * (0.4 + 0.3 * r[5]), y: h * 0.3)
                .blur(radius: 1.5)
        }
    }

    private var food: some View {
        ZStack {
            LinearGradient(colors: [Color(hue: 0.08, saturation: 0.4, brightness: 0.35),
                                    Color(hue: 0.07, saturation: 0.5, brightness: 0.2)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color(white: 0.96))
                .frame(width: min(w, h) * 0.78)
                .position(x: w * 0.5, y: h * 0.55)
                .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
            ForEach(0..<4, id: \.self) { i in
                Circle().fill(Color(hue: [0.02, 0.09, 0.26, 0.12][i] + 0.02 * r[10 + i],
                                    saturation: 0.7, brightness: 0.75 + 0.15 * r[14 + i]))
                    .frame(width: min(w, h) * (0.14 + 0.1 * r[18 + i]))
                    .position(x: w * (0.4 + 0.22 * r[22 + i]), y: h * (0.45 + 0.2 * r[26 + i]))
                    .blur(radius: 2.5)
            }
        }
    }

    private var screenshot: some View {
        ZStack {
            Color(white: 0.88)
            VStack(spacing: 0) {
                // Title bar with traffic lights
                HStack(spacing: 5) {
                    Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 8)
                    Circle().fill(Color(red: 1.0, green: 0.75, blue: 0.18)).frame(width: 8)
                    Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.26)).frame(width: 8)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Color(white: 0.94))
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.6))
                        .frame(width: w * 0.35, height: 8)
                    ForEach(0..<6, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.78))
                            .frame(width: w * (0.4 + 0.35 * r[10 + i]), height: 5)
                    }
                    Spacer()
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
            .padding(w * 0.08)
        }
    }
}

// MARK: - Render cache

@MainActor
final class Thumbs {
    static let shared = Thumbs()
    private let cache = NSCache<NSString, NSImage>()

    enum Bucket: CGFloat {
        case grid = 384
        case card = 800
        case zoom = 1600
    }

    func image(for photo: Photo, bucket: Bucket) -> NSImage {
        let key = "\(photo.seed)-\(bucket.rawValue)" as NSString
        if let img = cache.object(forKey: key) { return img }
        let aspect = photo.aspect
        let size = aspect >= 1
            ? CGSize(width: bucket.rawValue, height: (bucket.rawValue / aspect).rounded())
            : CGSize(width: (bucket.rawValue * aspect).rounded(), height: bucket.rawValue)
        let renderer = ImageRenderer(content: ArtworkView(seed: photo.seed, kind: photo.kind, size: size))
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 1
        let img = renderer.nsImage ?? NSImage(size: size)
        cache.setObject(img, forKey: key)
        return img
    }

    func prewarm(_ photos: [Photo]) {
        Task { @MainActor in
            for (i, p) in photos.enumerated() {
                _ = image(for: p, bucket: .grid)
                if i % 6 == 0 { await Task.yield() }
            }
        }
    }
}
