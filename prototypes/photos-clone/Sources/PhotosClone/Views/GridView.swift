import SwiftUI
import AppKit

struct SectionHeader: View {
    let section: DaySection

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(section.title)
                .font(.system(size: 15, weight: .semibold))
            if let loc = section.subtitle {
                Text(loc)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
        .background(.bar)
    }
}

struct GridView: View {
    let sections: [DaySection]
    let showsHeaders: Bool
    let inTrash: Bool
    let ns: Namespace.ID
    let onOpen: (UUID) -> Void

    @Environment(NavigationState.self) private var nav
    @Environment(MockLibrary.self) private var lib
    @Environment(SelectionModel.self) private var sel
    @FocusState private var gridFocused: Bool
    @State private var viewportWidth: CGFloat = 1000
    @State private var pinchBase: Double?

    private var spacing: CGFloat { 3 }
    private var cellSize: CGFloat { 80 + nav.zoomLevel * 176 }
    private var orderedIDs: [UUID] { sections.flatMap { $0.photos.map(\.id) } }
    private var totalCount: Int { sections.reduce(0) { $0 + $1.photos.count } }

    private var columnCount: Int {
        max(1, Int((viewportWidth - 20 + spacing) / (cellSize + spacing)))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if totalCount == 0 {
                    emptyState
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: cellSize, maximum: cellSize * 1.8), spacing: spacing)],
                        spacing: spacing,
                        pinnedViews: showsHeaders ? [.sectionHeaders] : []
                    ) {
                        ForEach(sections) { section in
                            Section {
                                ForEach(section.photos) { photo in
                                    ThumbnailCell(photo: photo, orderedIDs: orderedIDs, ns: ns,
                                                  inTrash: inTrash, onOpen: onOpen)
                                        .id(photo.id)
                                }
                            } header: {
                                if showsHeaders { SectionHeader(section: section) }
                            }
                        }
                    }
                    .padding(.horizontal, 10)

                    Text(footerText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 26)
                }
            }
            .defaultScrollAnchor(.bottom)
            .background(Color(nsColor: .textBackgroundColor))
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { viewportWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, w in viewportWidth = w }
                }
            }
            .onTapGesture { sel.clear() }
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        if pinchBase == nil { pinchBase = nav.zoomLevel }
                        var t = Transaction()
                        t.disablesAnimations = true
                        withTransaction(t) {
                            nav.zoomLevel = min(1, max(0, (pinchBase ?? 0.5) + (value.magnification - 1) * 0.6))
                        }
                    }
                    .onEnded { _ in
                        pinchBase = nil
                        withAnimation(Anim.zoom) { nav.zoomLevel = min(1, max(0, nav.zoomLevel)) }
                    }
            )
            .focusable()
            .focusEffectDisabled()
            .focused($gridFocused)
            .onAppear { gridFocused = true }
            .onKeyPress(phases: .down) { press in
                handleKey(press, proxy: proxy)
            }
            .onChange(of: nav.scrollTarget) { _, target in
                if let target {
                    proxy.scrollTo(target, anchor: .center)
                    nav.scrollTarget = nil
                }
            }
            .onChange(of: sel.focusedID) { _, id in
                if let id, nav.openedPhotoID == nil { proxy.scrollTo(id) }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            nav.searchText.isEmpty ? "No Photos" : "No Results",
            systemImage: nav.searchText.isEmpty ? "photo.on.rectangle" : "magnifyingglass",
            description: Text(nav.searchText.isEmpty
                              ? "Photos will appear here."
                              : "Check the spelling or try a new search.")
        )
        .frame(minHeight: 500)
    }

    private var footerText: String {
        let favs = sections.flatMap(\.photos).filter(\.isFavorite).count
        let base = "\(totalCount.formatted()) Photo\(totalCount == 1 ? "" : "s")"
        return favs > 0 ? "\(base) · \(favs) Favorite\(favs == 1 ? "" : "s")" : base
    }

    private func handleKey(_ press: KeyPress, proxy: ScrollViewProxy) -> KeyPress.Result {
        guard nav.openedPhotoID == nil else { return .ignored }
        let extend = press.modifiers.contains(.shift)
        switch press.key {
        case .leftArrow:
            sel.move(-1, ordered: orderedIDs, extend: extend)
            return .handled
        case .rightArrow:
            sel.move(1, ordered: orderedIDs, extend: extend)
            return .handled
        case .upArrow:
            sel.move(-columnCount, ordered: orderedIDs, extend: extend)
            return .handled
        case .downArrow:
            sel.move(columnCount, ordered: orderedIDs, extend: extend)
            return .handled
        case .return, .space:
            if let id = sel.focusedID ?? sel.selection.first {
                onOpen(id)
                return .handled
            }
            return .ignored
        case .escape:
            if !sel.selection.isEmpty {
                sel.clear()
                return .handled
            }
            return .ignored
        case .delete, .deleteForward:
            guard !sel.selection.isEmpty else { return .ignored }
            let ids = sel.selection
            withAnimation(Anim.zoom) {
                if inTrash { lib.eraseForever(ids) } else { lib.moveToTrash(ids) }
            }
            sel.clear()
            return .handled
        default:
            return .ignored
        }
    }
}
