import SwiftUI
import AppKit

struct DetailView: View {
    let photo: Photo
    let photosList: [Photo]
    let ns: Namespace.ID
    let onStep: (Int) -> Void
    let onSelect: (UUID) -> Void
    let onClose: () -> Void

    @Environment(NavigationState.self) private var nav
    @Environment(ContextLibrary.self) private var lib

    /// Which screen of this moment is on show. A moment is not one picture: you
    /// sat on this window for two minutes and the engine kept forty of them.
    @State private var index = 0
    @State private var screen: NSImage?

    private var shots: [Shot] { photo.shots }
    private var current: Shot? {
        guard shots.indices.contains(index) else { return shots.first }
        return shots[index]
    }

    var body: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack {
                    mainImage
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 12)
                .padding(.top, 10)

                filmstrip
                    .padding(.vertical, 8)
            }
        }
        .background { hiddenKeyButtons }
    }

    @ViewBuilder private var mainImage: some View {
        let img = Image(nsImage: screen ?? Thumbs.shared.card(for: photo, bucket: .zoom))
            .resizable()
            .scaledToFit()
            .id(photo.id)
        Group {
            if nav.heroActive {
                img.matchedGeometryEffect(id: photo.id, in: ns)
            } else {
                img.transition(.opacity)
            }
        }
        // Reloads on both counts: opening another moment, and stepping through
        // this one's screens.
        .task(id: "\(photo.id)-\(index)") {
            guard let current else { screen = nil; return }
            screen = await Thumbs.shared.screen(for: current, bucket: .zoom)
        }
        .onChange(of: photo.id) { _, _ in index = 0 }
    }

    /// The inside of this moment rather than the moments around it. Sixty
    /// captures of one window is what actually happened; walking them is watching
    /// the conversation arrive. Moving between moments stays on the arrow keys.
    @ViewBuilder private var filmstrip: some View {
        if shots.count > 1 {
            VStack(spacing: 5) {
                HStack(spacing: 6) {
                    Text(caption)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 3) {
                            ForEach(Array(shots.enumerated()), id: \.element.frameId) { i, shot in
                                ShotThumb(shot: shot, isCurrent: i == index)
                                    .onTapGesture { index = i }
                                    .id(shot.frameId)
                            }
                        }
                        .frame(height: 38)
                        .padding(.horizontal, 12)
                    }
                    .frame(height: 38)
                    .onChange(of: index) { _, i in
                        guard shots.indices.contains(i) else { return }
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(shots[i].frameId, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var caption: String {
        let f = Date.FormatStyle(date: .omitted, time: .shortened)
        let span = "\(photo.date.formatted(f)) – \(photo.lastSeen.formatted(f))"
        return "\(span)  ·  screen \(index + 1) of \(shots.count)"
    }

    /// Its own view so each thumbnail owns one load, cancelled the moment it
    /// scrolls out of the strip.
    private struct ShotThumb: View {
        let shot: Shot
        let isCurrent: Bool
        @State private var img: NSImage?

        var body: some View {
            Group {
                if let img {
                    Image(nsImage: img).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: 34, height: 34)
            .clipped()
            .overlay {
                if isCurrent {
                    Rectangle().strokeBorder(.white, lineWidth: 2)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                }
            }
            .opacity(isCurrent ? 1 : 0.75)
            .task(id: shot.frameId) {
                img = await Thumbs.shared.screen(for: shot, bucket: .grid)
            }
        }
    }

    private var hiddenKeyButtons: some View {
        Group {
            Button(action: { onStep(-1) }) { EmptyView() }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button(action: { onStep(1) }) { EmptyView() }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button(action: onClose) { EmptyView() }
                .keyboardShortcut(.escape, modifiers: [])
            Button(action: { lib.toggleFavorite([photo.id]) }) { EmptyView() }
                .keyboardShortcut(".", modifiers: [])
        }
        .buttonStyle(.plain)
        .opacity(0)
        .frame(width: 0, height: 0)
    }
}
