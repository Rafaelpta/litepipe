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
    @Environment(MockLibrary.self) private var lib

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
        let img = Image(nsImage: Thumbs.shared.image(for: photo, bucket: .zoom))
            .resizable()
            .scaledToFit()
            .id(photo.id)
        if nav.heroActive {
            img.matchedGeometryEffect(id: photo.id, in: ns)
        } else {
            img.transition(.opacity)
        }
    }

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 3) {
                    ForEach(photosList) { p in
                        Image(nsImage: Thumbs.shared.image(for: p, bucket: .grid))
                            .resizable()
                            .scaledToFill()
                            .frame(width: 34, height: 34)
                            .clipped()
                            .overlay {
                                if p.id == photo.id {
                                    Rectangle().strokeBorder(.white, lineWidth: 2)
                                        .shadow(color: .black.opacity(0.4), radius: 2)
                                }
                            }
                            .opacity(p.id == photo.id ? 1 : 0.75)
                            .onTapGesture { onSelect(p.id) }
                            .id(p.id)
                    }
                }
                .frame(height: 38)
                .padding(.horizontal, 12)
            }
            .frame(height: 38)
            .onAppear { proxy.scrollTo(photo.id, anchor: .center) }
            .onChange(of: photo.id) { _, id in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(id, anchor: .center)
                }
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
