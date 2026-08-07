import SwiftUI
import AppKit

struct ThumbnailCell: View {
    let photo: Photo
    let orderedIDs: [UUID]
    let ns: Namespace.ID
    let inTrash: Bool
    let onOpen: (UUID) -> Void

    @Environment(NavigationState.self) private var nav
    @Environment(ContextLibrary.self) private var lib
    @Environment(SelectionModel.self) private var sel
    @State private var hovering = false
    /// The screen itself, once it has been pulled out of its chunk. Nil until
    /// then, and nil forever for the captures that kept no picture.
    @State private var screen: NSImage?

    private var isSelected: Bool { sel.selection.contains(photo.id) }
    private var heroOwnedByDetail: Bool { nav.openedPhotoID == photo.id && nav.heroActive }

    var body: some View {
        Group {
            if heroOwnedByDetail {
                square
            } else {
                square.matchedGeometryEffect(id: photo.id, in: ns)
            }
        }
        .overlay {
            if isSelected {
                Rectangle().strokeBorder(Color.accentColor, lineWidth: 3)
            }
        }
        .overlay(alignment: .bottomLeading) { heart }
        .overlay(alignment: .topTrailing) { dwellBadge }
        .contentShape(Rectangle())
        .onHover { h in
            withAnimation(Anim.hover) { hovering = h }
        }
        .gesture(TapGesture(count: 2).onEnded { onOpen(photo.id) })
        .simultaneousGesture(TapGesture().onEnded {
            sel.click(photo.id, ordered: orderedIDs, modifiers: NSEvent.modifierFlags)
        })
        .contextMenu { menuItems }
    }

    /// The screen at rest, the text on hover. A wall of real screens is read at a
    /// glance — you recognise the conversation before you can read a word of it —
    /// but the text is what the archive is actually for, so it is one pointer
    /// move away rather than gone.
    private var square: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let screen {
                    Image(nsImage: screen)
                        .resizable()
                        .scaledToFill()
                } else {
                    // Also the permanent state for a capture with no picture.
                    Image(nsImage: Thumbs.shared.card(for: photo, bucket: .grid))
                        .resizable()
                        .scaledToFill()
                }
            }
            .overlay {
                if hovering, screen != nil {
                    Image(nsImage: Thumbs.shared.card(for: photo, bucket: .grid))
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipped()
            // Cancelled when the cell scrolls away, so the store never works on
            // screens nobody is looking at any more.
            .task(id: photo.id) {
                screen = await Thumbs.shared.screen(for: photo, bucket: .grid)
            }
    }

    /// A collapsed run of identical captures reads as time spent on one screen.
    @ViewBuilder private var dwellBadge: some View {
        if photo.repeatCount > 1 {
            Text(dwellLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(5)
        }
    }

    private var dwellLabel: String {
        let secs = Int(photo.dwell)
        if secs >= 90 { return "\(secs / 60) min" }
        if secs >= 5 { return "\(secs)s" }
        return "×\(photo.repeatCount)"
    }

    @ViewBuilder private var heart: some View {
        if (hovering || photo.isFavorite) && !inTrash {
            Button {
                lib.toggleFavorite(effectiveIDs)
            } label: {
                Image(systemName: photo.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.55), radius: 2)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .symbolEffect(.bounce, value: photo.isFavorite)
            .transition(.opacity)
        }
    }

    private var effectiveIDs: Set<UUID> {
        sel.selection.contains(photo.id) ? sel.selection : [photo.id]
    }

    private var countLabel: String {
        let n = effectiveIDs.count
        return n == 1 ? "Photo" : "\(n) Photos"
    }

    @ViewBuilder private var menuItems: some View {
        if inTrash {
            Button("Restore") {
                withAnimation(Anim.zoom) { lib.restore(effectiveIDs) }
                sel.clear()
            }
            Divider()
            Button("Delete \(countLabel) Permanently", role: .destructive) {
                withAnimation(Anim.zoom) { lib.eraseForever(effectiveIDs) }
                sel.clear()
            }
        } else {
            Button("Get Info") {
                if !sel.selection.contains(photo.id) {
                    sel.click(photo.id, ordered: orderedIDs, modifiers: [])
                }
                nav.showInspector = true
            }
            Button(photo.isFavorite ? "Unfavorite" : "Favorite") {
                lib.toggleFavorite(effectiveIDs)
            }
            Button("Duplicate \(countLabel)") {
                withAnimation(Anim.zoom) { lib.duplicate(effectiveIDs) }
            }
            Button(photo.isHidden ? "Unhide \(countLabel)" : "Hide \(countLabel)") {
                withAnimation(Anim.zoom) { lib.hide(effectiveIDs) }
                sel.clear()
            }
            Divider()
            Button("Delete \(countLabel)", role: .destructive) {
                withAnimation(Anim.zoom) { lib.moveToTrash(effectiveIDs) }
                sel.clear()
            }
        }
    }
}
