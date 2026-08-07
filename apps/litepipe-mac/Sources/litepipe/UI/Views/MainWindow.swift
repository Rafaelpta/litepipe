import SwiftUI
import AppKit

struct MainWindow: View {
    @Environment(NavigationState.self) private var nav
    @Environment(ContextLibrary.self) private var lib

    var body: some View {
        @Bindable var nav = nav
        NavigationSplitView {
            SidebarView()
        } detail: {
            ContentColumn()
                .searchable(text: $nav.searchText, placement: .toolbar, prompt: "Search")
                .inspector(isPresented: $nav.showInspector) {
                    InspectorView()
                }
                .toolbarBackground(.visible, for: .windowToolbar)
        }
        .navigationTitle(nav.sidebarItem.displayName)
        .frame(minWidth: 940, minHeight: 620)
        // The archive was read once, at launch, so anything captured while the
        // window stayed open never appeared. Only the newest page is re-read,
        // which is cheap however far back the archive goes.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if !Task.isCancelled { lib.refreshHead() }
            }
        }
    }
}

struct ContentColumn: View {
    @Environment(NavigationState.self) private var nav
    @Environment(ContextLibrary.self) private var lib
    @Environment(SelectionModel.self) private var sel
    @Environment(ChatModel.self) private var chat
    @Namespace private var heroNS

    /// `monitor_1` is the engine's name for it, not a person's.
    private func displayName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "monitor_1": "Main display"
        case "monitor_2": "Second display"
        case "monitor_3": "Third display"
        default: raw
        }
    }

    private var isTimeline: Bool { nav.sidebarItem == .timeline }
    private var inTrash: Bool { nav.sidebarItem == .recentlyDeleted }

    private var currentPhotos: [Photo] {
        lib.photos(for: nav.sidebarItem, search: nav.searchText,
                   favoritesOnly: nav.favoritesOnly, monitor: nav.monitor)
    }

    var body: some View {
        ZStack {
            mainContent

            if let id = nav.openedPhotoID, let photo = lib.photo(id) {
                DetailView(
                    photo: photo,
                    photosList: currentPhotos,
                    ns: heroNS,
                    onStep: step,
                    onSelect: jump,
                    onClose: closeDetail
                )
                .zIndex(2)
                .transition(.opacity)
            }
        }
        .toolbar { toolbarContent }
    }

    @ViewBuilder private var mainContent: some View {
        let photos = currentPhotos
        if nav.sidebarItem == .assistant {
            ChatPane()
        } else if nav.sidebarItem == .places {
            MapPane(photos: photos)
        } else {
            gridModes(photos)
        }
    }

    @ViewBuilder private func gridModes(_ photos: [Photo]) -> some View {
        let mode: ViewMode = isTimeline ? nav.viewMode : (nav.sidebarItem == .dayRecaps ? .days : .all)
        ZStack {
            switch mode {
            case .years:
                YearsView(groups: lib.yearGroups(photos)) { year in
                    drill(to: .months, anchor: photos.first {
                        Calendar.current.isDate($0.date, equalTo: year, toGranularity: .year)
                    })
                }
                .transition(drillTransition)
            case .months:
                MonthsView(groups: lib.monthGroups(photos)) { month in
                    drill(to: .days, anchor: photos.first {
                        Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month)
                    })
                }
                .transition(drillTransition)
            case .days:
                GridView(sections: lib.daySections(photos),
                         showsHeaders: true,
                         inTrash: inTrash,
                         ns: heroNS,
                         onOpen: openDetail)
                    .transition(drillTransition)
            case .all:
                GridView(sections: flatSections(photos),
                         showsHeaders: false,
                         inTrash: inTrash,
                         ns: heroNS,
                         onOpen: openDetail)
                    .transition(drillTransition)
            }
        }
    }

    private var drillTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 1.03).combined(with: .opacity),
            removal: .scale(scale: 0.97).combined(with: .opacity)
        )
    }

    private func flatSections(_ photos: [Photo]) -> [DaySection] {
        [DaySection(id: .distantPast, title: "", subtitle: nil, photos: photos)]
    }

    // MARK: - Detail open/close/step

    private func openDetail(_ id: UUID) {
        nav.heroActive = true
        sel.selection = [id]
        sel.anchor = id
        sel.focusedID = id
        withAnimation(Anim.openDetail) { nav.openedPhotoID = id }
    }

    private func closeDetail() {
        guard let id = nav.openedPhotoID else { return }
        nav.heroActive = true
        nav.scrollTarget = id
        DispatchQueue.main.async {
            withAnimation(Anim.closeDetail) { nav.openedPhotoID = nil }
        }
    }

    private func step(_ delta: Int) {
        guard let cur = nav.openedPhotoID else { return }
        let list = currentPhotos
        guard let i = list.firstIndex(where: { $0.id == cur }),
              list.indices.contains(i + delta) else { return }
        jump(list[i + delta].id)
    }

    private func jump(_ id: UUID) {
        nav.heroActive = false
        withAnimation(Anim.crossfade) { nav.openedPhotoID = id }
        sel.selection = [id]
        sel.anchor = id
        sel.focusedID = id
    }

    private func drill(to mode: ViewMode, anchor: Photo?) {
        withAnimation(Anim.drill) { nav.viewMode = mode }
        if mode == .days, let anchor {
            DispatchQueue.main.async { nav.scrollTarget = anchor.id }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        if nav.openedPhotoID == nil {
            gridToolbar
        } else {
            detailToolbar
        }
    }

    @ToolbarContentBuilder private var gridToolbar: some ToolbarContent {
        if nav.sidebarItem == .assistant {
            ToolbarItem {
                Button { chat.reset() } label: { Label("New Chat", systemImage: "square.and.pencil") }
                    .help("Start a new conversation")
                    .disabled(chat.turns.isEmpty)
            }
        }
        if isTimeline {
            ToolbarItem(placement: .principal) {
                @Bindable var nav = nav
                Picker("View", selection: Binding(
                    get: { nav.viewMode },
                    set: { newMode in withAnimation(Anim.drill) { nav.viewMode = newMode } }
                )) {
                    ForEach(ViewMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
        ToolbarItemGroup {
            if nav.sidebarItem != .assistant {
            Picker("Mode", selection: Binding(
                get: { nav.rawMode },
                set: { raw in
                    nav.rawMode = raw
                    lib.setRawMode(raw)
                    sel.clear()
                }
            )) {
                Text("Moments").tag(false)
                Text("Raw captures").tag(true)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .help("Show folded moments or every capture as recorded")
            }

            // Only worth the space on a machine with more than one screen. The
            // engine captures every display at once, so without this every window
            // appears twice: once under a picture of the display it was not on.
            if lib.monitors.count > 1, nav.sidebarItem != .assistant {
                Picker("Display", selection: Binding(
                    get: { nav.monitor },
                    set: { nav.monitor = $0; sel.clear() }
                )) {
                    Text("All displays").tag(String?.none)
                    ForEach(lib.monitors, id: \.self) { m in
                        Text(displayName(m)).tag(String?.some(m))
                    }
                }
                .fixedSize()
                .help("A capture's text comes from the window in focus, its picture from a whole screen. On the screen that did not hold the focused window the two will not match.")
            }

            if nav.sidebarItem != .places, nav.sidebarItem != .assistant,
               !isTimeline || nav.viewMode == .days || nav.viewMode == .all {
                Slider(value: Binding(
                    get: { nav.zoomLevel },
                    set: { v in withAnimation(Anim.zoom) { nav.zoomLevel = v } }
                ), in: 0...1)
                .frame(width: 110)
                .controlSize(.small)
                .help("Change the size of the thumbnails")
            }
            Menu {
                Picker("Filter", selection: Binding(
                    get: { nav.favoritesOnly },
                    set: { nav.favoritesOnly = $0 }
                )) {
                    Text("All Items").tag(false)
                    Text("Favorites").tag(true)
                }
                .pickerStyle(.inline)
            } label: {
                Label("Filter", systemImage: nav.favoritesOnly
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
            }
            .help("Filter what is shown")

            Button {
                nav.showInspector.toggle()
            } label: {
                Label("Info", systemImage: "info.circle")
            }
            .help("Get info on the selected capture")
        }
    }

    @ToolbarContentBuilder private var detailToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                closeDetail()
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .help("Back to the grid")
        }
        ToolbarItem(placement: .principal) {
            if let id = nav.openedPhotoID, let photo = lib.photo(id) {
                VStack(spacing: 0) {
                    Text(photo.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 12, weight: .semibold))
                    Text(photo.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        ToolbarItemGroup {
            Button { step(-1) } label: { Label("Previous", systemImage: "chevron.left") }
                .disabled(!canStep(-1))
                .help("Previous capture")
            Button { step(1) } label: { Label("Next", systemImage: "chevron.right") }
                .disabled(!canStep(1))
                .help("Next capture")
            if let id = nav.openedPhotoID, let photo = lib.photo(id) {
                Button {
                    lib.toggleFavorite([id])
                } label: {
                    Label("Favorite", systemImage: photo.isFavorite ? "heart.fill" : "heart")
                }
                .help("Add this capture to Highlights")
                Button {
                    let next = nextAfterDelete(id)
                    withAnimation(Anim.zoom) { lib.moveToTrash([id]) }
                    if let next { jump(next) } else { closeDetailImmediately() }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .help("Move this capture to Recently Deleted")
            }
            Button {
                nav.showInspector.toggle()
            } label: {
                Label("Info", systemImage: "info.circle")
            }
            .help("Get info on the selected capture")
        }
    }

    private func canStep(_ delta: Int) -> Bool {
        guard let cur = nav.openedPhotoID,
              let i = currentPhotos.firstIndex(where: { $0.id == cur }) else { return false }
        return currentPhotos.indices.contains(i + delta)
    }

    private func nextAfterDelete(_ id: UUID) -> UUID? {
        let list = currentPhotos
        guard let i = list.firstIndex(where: { $0.id == id }) else { return nil }
        if list.indices.contains(i + 1) { return list[i + 1].id }
        if list.indices.contains(i - 1) { return list[i - 1].id }
        return nil
    }

    private func closeDetailImmediately() {
        nav.heroActive = false
        withAnimation(Anim.crossfade) { nav.openedPhotoID = nil }
        nav.heroActive = true
    }
}
