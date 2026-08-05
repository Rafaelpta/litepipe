import SwiftUI

/// Mock "Map" collection — a stylized map with photo pins, like Photos' Map view.
struct MapPane: View {
    let photos: [Photo]

    private struct Pin: Identifiable {
        let id: UUID
        let photo: Photo
        let x: CGFloat
        let y: CGFloat
        let count: Int
    }

    private var pins: [Pin] {
        let withLocation = photos.filter { $0.location != nil }
        let byLocation = Dictionary(grouping: withLocation, by: { $0.location! })
        var result: [Pin] = []
        var rng = SplitMix64(seed: 0x4D41_5050)
        for (_, group) in byLocation.sorted(by: { $0.key < $1.key }) {
            guard let hero = group.first(where: \.isFavorite) ?? group.first else { continue }
            let x = 0.12 + CGFloat(Double.random(in: 0...1, using: &rng)) * 0.76
            let y = 0.15 + CGFloat(Double.random(in: 0...1, using: &rng)) * 0.7
            result.append(Pin(id: hero.id, photo: hero, x: x, y: y, count: group.count))
        }
        return result
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Land
                LinearGradient(colors: [Color(hue: 0.24, saturation: 0.10, brightness: 0.93),
                                        Color(hue: 0.20, saturation: 0.14, brightness: 0.88)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                // Water
                Ellipse()
                    .fill(Color(hue: 0.55, saturation: 0.30, brightness: 0.88))
                    .frame(width: geo.size.width * 0.7, height: geo.size.height * 0.5)
                    .position(x: geo.size.width * 0.85, y: geo.size.height * 0.9)
                    .blur(radius: 18)
                // Roads
                roads(in: geo.size)
                    .stroke(.white.opacity(0.85), lineWidth: 4)
                roads(in: geo.size)
                    .stroke(Color(white: 0.75).opacity(0.5), lineWidth: 5)
                    .blur(radius: 1.5)
                // Park
                RoundedRectangle(cornerRadius: 40)
                    .fill(Color(hue: 0.3, saturation: 0.25, brightness: 0.82).opacity(0.7))
                    .frame(width: geo.size.width * 0.2, height: geo.size.height * 0.22)
                    .position(x: geo.size.width * 0.22, y: geo.size.height * 0.75)
                    .blur(radius: 6)

                ForEach(pins) { pin in
                    pinView(pin)
                        .position(x: pin.x * geo.size.width, y: pin.y * geo.size.height)
                }

                // Zoom controls, bottom-right like Maps
                VStack(spacing: 0) {
                    Button {} label: { Image(systemName: "plus").frame(width: 28, height: 26) }
                    Divider().frame(width: 28)
                    Button {} label: { Image(systemName: "minus").frame(width: 28, height: 26) }
                }
                .buttonStyle(.plain)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(14)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func roads(in size: CGSize) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: size.height * 0.35))
            p.addCurve(to: CGPoint(x: size.width, y: size.height * 0.5),
                       control1: CGPoint(x: size.width * 0.35, y: size.height * 0.2),
                       control2: CGPoint(x: size.width * 0.6, y: size.height * 0.7))
            p.move(to: CGPoint(x: size.width * 0.3, y: 0))
            p.addCurve(to: CGPoint(x: size.width * 0.55, y: size.height),
                       control1: CGPoint(x: size.width * 0.42, y: size.height * 0.4),
                       control2: CGPoint(x: size.width * 0.4, y: size.height * 0.7))
        }
    }

    private func pinView(_ pin: Pin) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: Thumbs.shared.image(for: pin.photo, bucket: .grid))
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            if pin.count > 1 {
                Text("\(pin.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())
                    .offset(x: 8, y: -8)
            }
        }
    }
}
