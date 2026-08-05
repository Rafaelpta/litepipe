import AppKit
import Observation

@Observable
final class SelectionModel {
    var selection: Set<UUID> = []
    var anchor: UUID?
    var focusedID: UUID?

    func click(_ id: UUID, ordered: [UUID], modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            anchor = id
        } else if modifiers.contains(.shift), let a = anchor,
                  let ai = ordered.firstIndex(of: a), let bi = ordered.firstIndex(of: id) {
            selection = Set(ordered[min(ai, bi)...max(ai, bi)])
        } else {
            selection = [id]
            anchor = id
        }
        focusedID = id
    }

    /// Moves keyboard focus by `delta` in the flattened order. Returns the new focused id for scrolling.
    @discardableResult
    func move(_ delta: Int, ordered: [UUID], extend: Bool) -> UUID? {
        guard !ordered.isEmpty else { return nil }
        let current = focusedID ?? selection.first ?? ordered.last
        guard let ci = ordered.firstIndex(of: current ?? ordered.last!) else { return nil }
        let ni = min(max(ci + delta, 0), ordered.count - 1)
        let id = ordered[ni]
        if extend, let a = anchor, let ai = ordered.firstIndex(of: a) {
            selection = Set(ordered[min(ai, ni)...max(ai, ni)])
        } else {
            selection = [id]
            anchor = id
        }
        focusedID = id
        return id
    }

    func selectAll(_ ordered: [UUID]) {
        selection = Set(ordered)
        anchor = ordered.first
        focusedID = ordered.last
    }

    func clear() {
        selection = []
        anchor = nil
        focusedID = nil
    }
}
