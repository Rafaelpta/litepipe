import SwiftUI

struct SidebarView: View {
    @Environment(NavigationState.self) private var nav
    @Environment(MockLibrary.self) private var lib
    @Environment(SelectionModel.self) private var sel

    var body: some View {
        @Bindable var nav = nav
        List(selection: $nav.sidebarItem) {
            Section("Photos") {
                row(.library, "photo.on.rectangle.angled")
                row(.favorites, "heart")
                row(.map, "map")
                row(.recentlySaved, "square.and.arrow.down")
                HStack {
                    Label("Recently Deleted", systemImage: "trash")
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .tag(SidebarItem.recentlyDeleted)
            }

            Section("Collections") {
                row(.days, "clock")
                row(.peoplePets, "person.crop.circle")
                row(.memories, "memories")
                row(.trips, "suitcase")
                row(.featured, "photo.artframe")

                DisclosureGroup(isExpanded: $nav.utilitiesExpanded) {
                    row(.duplicates, "square.on.square", nested: true)
                    row(.receipts, "cart", nested: true)
                    row(.handwriting, "pencil.line", nested: true)
                    row(.illustrations, "scribble.variable", nested: true)
                    row(.recentlyViewed, "eye", nested: true)
                    row(.documents, "doc.text", nested: true)
                } label: {
                    Label("Utilities", systemImage: "wrench.and.screwdriver")
                        .tag(SidebarItem.utilities)
                }

                DisclosureGroup(isExpanded: $nav.mediaTypesExpanded) {
                    row(.videos, "video", nested: true)
                    row(.selfies, "person.crop.square", nested: true)
                    row(.livePhotos, "livephoto", nested: true)
                    row(.portrait, "f.cursive", nested: true)
                    row(.panoramas, "pano", nested: true)
                    row(.timelapse, "timelapse", nested: true)
                    row(.slomo, "slowmo", nested: true)
                    row(.bursts, "square.stack.3d.down.right", nested: true)
                    row(.screenshots, "camera.viewfinder", nested: true)
                    row(.screenRecordings, "record.circle", nested: true)
                    row(.animated, "wave.3.left", nested: true)
                } label: {
                    Label("Media Types", systemImage: "folder")
                        .tag(SidebarItem.mediaTypes)
                }

                DisclosureGroup(isExpanded: $nav.albumsExpanded) {
                    ForEach(lib.albumNames, id: \.self) { name in
                        row(.album(name), "rectangle.stack", nested: true)
                    }
                } label: {
                    Label("Albums", systemImage: "folder")
                        .tag(SidebarItem.albumsRoot)
                }

                DisclosureGroup(isExpanded: $nav.projectsExpanded) {
                    EmptyView()
                } label: {
                    Label("Projects", systemImage: "folder")
                        .tag(SidebarItem.projects)
                }
            }

            Section("Sharing") {
                DisclosureGroup(isExpanded: $nav.sharedAlbumsExpanded) {
                    row(.activity, "text.bubble", nested: true)
                    ForEach(lib.sharedAlbumNames, id: \.self) { name in
                        row(.sharedAlbum(name), "photo.stack", nested: true)
                    }
                } label: {
                    Label("Shared Albums", systemImage: "rectangle.stack.badge.person.crop")
                        .tag(SidebarItem.sharedAlbums)
                }
                row(.sharedWithYou, "shared.with.you")
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        .onChange(of: nav.sidebarItem) {
            sel.clear()
            nav.openedPhotoID = nil
            nav.heroActive = true
        }
    }

    /// Top-level rows get the accent-tinted icon; rows nested inside a disclosure
    /// group get a secondary (gray) icon, matching Photos.
    private func row(_ item: SidebarItem, _ icon: String, nested: Bool = false) -> some View {
        Label {
            Text(item.displayName)
        } icon: {
            if nested {
                Image(systemName: icon).foregroundStyle(.secondary)
            } else {
                Image(systemName: icon)
            }
        }
        .tag(item)
    }
}
