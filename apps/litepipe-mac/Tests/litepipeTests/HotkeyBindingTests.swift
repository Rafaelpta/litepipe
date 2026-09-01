import XCTest
import AppKit
@testable import litepipe

/// The shortcut that pauses capture used to be a bare ⌃⌥ chord, which fired on
/// modifier release and so could not tell a deliberate press from a hand passing
/// through on the way somewhere else. These are the rules that replace it.
final class HotkeyBindingTests: XCTestCase {

    private let controlOptionP = HotkeyBinding(keyCode: 35, modifiers: [.control, .option], label: "P")!

    func testAStoredBindingSurvivesTheRoundTrip() {
        let parsed = HotkeyBinding(encoded: controlOptionP.encoded())
        XCTAssertEqual(parsed, controlOptionP)
    }

    func testNoStoredValueMeansNoShortcut() {
        XCTAssertNil(HotkeyBinding(encoded: ""))
    }

    func testAKeyWithNoModifiersIsRefused() {
        XCTAssertNil(HotkeyBinding(keyCode: 35, modifiers: [], label: "P"))
    }

    func testTheBoundKeyWithItsModifiersFires() {
        XCTAssertTrue(controlOptionP.matches(keyCode: 35, flags: [.control, .option]))
    }

    func testModifiersAloneDoNotFire() {
        XCTAssertFalse(controlOptionP.matches(keyCode: 58, flags: [.control, .option]))
    }

    /// ⌃⌥⌘P belongs to whatever app the user is actually talking to.
    func testAnExtraModifierIsADifferentShortcut() {
        XCTAssertFalse(controlOptionP.matches(keyCode: 35, flags: [.control, .option, .command]))
    }

    func testCapsLockDoesNotBreakTheMatch() {
        XCTAssertTrue(controlOptionP.matches(keyCode: 35, flags: [.control, .option, .capsLock]))
    }

    // MARK: - Naming the key

    func testALetterIsShownInUpperCase() {
        XCTAssertEqual(HotkeyBinding.name(forKeyCode: 35, characters: "p"), "P")
    }

    func testKeysThatPrintNothingAreNamed() {
        XCTAssertEqual(HotkeyBinding.name(forKeyCode: 49, characters: " "), "Space")
        XCTAssertEqual(HotkeyBinding.name(forKeyCode: 36, characters: "\r"), "Return")
    }

    func testAnUnknownSilentKeyStillGetsAName() {
        XCTAssertFalse(HotkeyBinding.name(forKeyCode: 999, characters: "").isEmpty)
    }

    // MARK: - What a stored setting means

    func testAnUntouchedSettingIsTheDefaultShortcut() {
        XCTAssertEqual(HotkeyBinding.resolve(stored: nil), HotkeyBinding.fallback)
    }

    func testAClearedSettingMeansNoShortcutAtAll() {
        XCTAssertNil(HotkeyBinding.resolve(stored: ""))
    }

    func testAStoredSettingWins() {
        let chosen = HotkeyBinding(keyCode: 49, modifiers: [.command, .shift], label: "Space")!
        XCTAssertEqual(HotkeyBinding.resolve(stored: chosen.encoded()), chosen)
    }

    func testACorruptSettingFallsBackToNoShortcutRatherThanCrashing() {
        XCTAssertNil(HotkeyBinding.resolve(stored: "not-a-binding"))
    }

    func testTheDefaultShortcutHasARealKey() {
        XCTAssertEqual(HotkeyBinding.fallback.keycaps(), ["⌃", "⌥", "P"])
    }

    func testKeycapsReadInTheOrderMacOSPrints() {
        let binding = HotkeyBinding(keyCode: 35, modifiers: [.command, .shift, .option, .control], label: "P")!
        XCTAssertEqual(binding.keycaps(), ["⌃", "⌥", "⇧", "⌘", "P"])
    }
}
