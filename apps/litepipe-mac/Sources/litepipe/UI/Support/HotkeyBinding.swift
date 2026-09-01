import AppKit

/// A shortcut the user can change: a real key plus the modifiers held with it.
///
/// The key is the point. The shortcut this replaces was modifiers alone, which
/// fires on release and so cannot tell a deliberate press from a hand on its way
/// to some other app's shortcut. Requiring a key means the toggle happens on a
/// key press or not at all.
struct HotkeyBinding: Equatable {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags
    /// What the key prints, for the settings pane. Captured when the shortcut is
    /// recorded so the pane never needs a keycode-to-name table.
    let label: String

    /// The modifiers a shortcut can be built from. Caps lock and the function key
    /// are deliberately absent: they say something about the keyboard's state
    /// rather than about what the user pressed.
    static let usable: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    init?(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, label: String) {
        let held = modifiers.intersection(Self.usable)
        // A global shortcut with no modifier would swallow the plain key from
        // every other application on the machine.
        guard !held.isEmpty else { return nil }
        self.keyCode = keyCode
        self.modifiers = held
        self.label = label
    }

    // MARK: - Storage

    /// `modifiers,keyCode,label` — the label last so it can hold anything.
    func encoded() -> String { "\(modifiers.rawValue),\(keyCode),\(label)" }

    init?(encoded: String) {
        let parts = encoded.split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3,
              let raw = UInt(parts[0]),
              let code = UInt16(parts[1])
        else { return nil }
        self.init(keyCode: code,
                  modifiers: NSEvent.ModifierFlags(rawValue: raw),
                  label: String(parts[2]))
    }

    // MARK: - Naming the key

    /// Keys that print nothing, so the settings pane shows a word instead of a
    /// blank keycap.
    private static let namedKeys: [UInt16: String] = [
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 117: "Forward Delete",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
    ]

    /// What to print on the keycap for a key the user just pressed.
    static func name(forKeyCode keyCode: UInt16, characters: String?) -> String {
        if let named = namedKeys[keyCode] { return named }
        let trimmed = (characters ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let scalar = trimmed.unicodeScalars.first, !CharacterSet.controlCharacters.contains(scalar) {
            return trimmed.uppercased()
        }
        return "Key \(keyCode)"
    }

    // MARK: - Storage semantics

    /// Where the user's choice lives, alongside the app's other settings.
    static let defaultsKey = "shortcut.pauseResume"

    /// ⌃⌥P. Close to the chord people already know, but with a key.
    static let fallback = HotkeyBinding(keyCode: 35, modifiers: [.control, .option], label: "P")!

    /// Absent means the user has never chosen, so they get the default. Empty
    /// means they cleared it on purpose and want no shortcut at all. The two
    /// have to stay distinguishable or clearing the shortcut would silently
    /// restore it on the next launch.
    static func resolve(stored: String?) -> HotkeyBinding? {
        guard let stored else { return fallback }
        return HotkeyBinding(encoded: stored)
    }

    /// The shortcut in force, or nil when there is none.
    static var current: HotkeyBinding? {
        get { resolve(stored: UserDefaults.standard.string(forKey: defaultsKey)) }
        set { UserDefaults.standard.set(newValue?.encoded() ?? "", forKey: defaultsKey) }
    }

    // MARK: - Matching

    /// True only for this key with exactly these modifiers. Exactly matters:
    /// ⌃⌥⌘P is a different shortcut from ⌃⌥P and belongs to whichever app the
    /// user is actually typing into.
    func matches(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        keyCode == self.keyCode && flags.intersection(Self.usable) == modifiers
    }

    func matches(_ event: NSEvent) -> Bool {
        matches(keyCode: event.keyCode, flags: event.modifierFlags)
    }

    // MARK: - Display

    /// In the order macOS prints them, so the pane reads like a menu.
    func keycaps() -> [String] {
        var caps: [String] = []
        if modifiers.contains(.control) { caps.append("⌃") }
        if modifiers.contains(.option) { caps.append("⌥") }
        if modifiers.contains(.shift) { caps.append("⇧") }
        if modifiers.contains(.command) { caps.append("⌘") }
        caps.append(label)
        return caps
    }
}
