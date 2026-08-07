import SwiftUI

struct YearsView: View {
    let groups: [(year: Date, photos: [Photo])]
    let onDrill: (Date) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                ForEach(groups, id: \.year) { group in
                    CollageCard(
                        photos: group.photos,
                        title: group.year.formatted(.dateTime.year()),
                        height: 320
                    ) { onDrill(group.year) }
                }
            }
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
            .padding(28)
        }
        .defaultScrollAnchor(.bottom)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

struct MonthsView: View {
    let groups: [(month: Date, photos: [Photo])]
    let onDrill: (Date) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 460), spacing: 18)], spacing: 18) {
                ForEach(groups, id: \.month) { group in
                    CollageCard(
                        photos: group.photos,
                        title: monthTitle(group.month),
                        height: 230
                    ) { onDrill(group.month) }
                }
            }
            .padding(28)
        }
        .defaultScrollAnchor(.bottom)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func monthTitle(_ month: Date) -> String {
        let cal = Calendar.current
        if cal.component(.year, from: month) == cal.component(.year, from: Date()) {
            return month.formatted(.dateTime.month(.wide))
        }
        return month.formatted(.dateTime.month(.wide).year())
    }
}

private struct CollageCard: View {
    let photos: [Photo]
    let title: String
    let height: CGFloat
    let action: () -> Void

    @State private var hovering = false

    /// Prefer a real screenshot for the cover; fall back to the longest capture.
    private var hero: Photo? {
        photos.first { $0.isFavorite && $0.hasImage }
            ?? photos.first(where: \.hasImage)
            ?? photos.max { $0.textLength < $1.textLength }
            ?? photos.first
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                if let hero {
                    Color.clear
                        .overlay {
                            ScreenImage(photo: hero, bucket: .card)
                                .scaledToFill()
                        }
                }
                LinearGradient(colors: [.black.opacity(0.45), .clear],
                               startPoint: .top, endPoint: .center)
                Text(title)
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                    .padding(18)
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(hovering ? 1.012 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(Anim.hover) { hovering = h }
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
