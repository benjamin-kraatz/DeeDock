import AppKit
import Carbon
import Foundation
import Testing
@testable import DeeDock

/// How the recorder reads key presses, how combinations encode for Carbon, and which ones collide
/// with DOKK's own shortcuts or the system's.
struct FlixShortcutTests {
    @Test func theDefaultIsControlOptionCommandF() {
        #expect(FlixShortcutCombo.default.keyCode == UInt16(kVK_ANSI_F))
        #expect(FlixShortcutCombo.default.modifiers.carbon == UInt32(controlKey | optionKey | cmdKey))
        #expect(FlixShortcutCombo.default.modifiers.symbols == "⌃⌥⌘")
        #expect(FlixShortcutConflict.conflict(for: .default) == nil)
    }

    @Test func modifiersEncodeForCarbonAndDrawInAppleOrder() {
        let all: FlixShortcutCombo.Modifiers = [.command, .shift, .option, .control]
        #expect(all.symbols == "⌃⌥⇧⌘")
        #expect(all.carbon == UInt32(controlKey | optionKey | shiftKey | cmdKey))
        #expect(FlixShortcutCombo.Modifiers(NSEvent.ModifierFlags([.command, .shift, .capsLock])) == [.command, .shift])
    }

    @Test func plainKeysAndShiftOnlyNeedAModifier() {
        let f = UInt16(kVK_ANSI_F)
        #expect(FlixShortcutCombo.recording(keyCode: f, modifiers: []) == .needsModifier)
        #expect(FlixShortcutCombo.recording(keyCode: f, modifiers: [.shift]) == .needsModifier)
        #expect(FlixShortcutCombo.recording(keyCode: f, modifiers: [.option])
                == .combo(FlixShortcutCombo(keyCode: f, modifiers: [.option])))
    }

    @Test func modifierKeysAloneKeepTheRecorderListening() {
        #expect(FlixShortcutCombo.recording(keyCode: UInt16(kVK_Command), modifiers: [.command]) == .incomplete)
        #expect(FlixShortcutCombo.recording(keyCode: UInt16(kVK_Option), modifiers: [.option]) == .incomplete)
    }

    @Test func functionKeysWorkWithoutModifiers() {
        let f5 = UInt16(kVK_F5)
        #expect(FlixShortcutCombo.recording(keyCode: f5, modifiers: []) == .combo(FlixShortcutCombo(keyCode: f5, modifiers: [])))
    }

    @Test func dokksOwnShortcutsAreRefused() {
        let space = UInt16(kVK_Space)
        let radar = FlixShortcutConflict.conflict(for: FlixShortcutCombo(keyCode: space, modifiers: [.option, .shift, .command]))
        let findWindow = FlixShortcutConflict.conflict(for: FlixShortcutCombo(keyCode: space, modifiers: [.shift, .command]))
        let robi = FlixShortcutConflict.conflict(for: FlixShortcutCombo(keyCode: UInt16(kVK_ANSI_R), modifiers: [.option, .shift, .command]))
        #expect(radar == .radar && radar?.refuses == true)
        #expect(findWindow == .radar)
        #expect(robi == .robi && robi?.refuses == true)
        #expect(FlixShortcutConflict.conflict(for: FlixShortcutCombo(keyCode: UInt16(kVK_ANSI_Q), modifiers: [.command]))?.refuses == true)
    }

    @Test func spotlightAndLauncherCombinationsOnlyWarn() {
        let space = UInt16(kVK_Space)
        let spotlight = FlixShortcutConflict.conflict(for: FlixShortcutCombo(keyCode: space, modifiers: [.command]))
        let launcher = FlixShortcutConflict.conflict(for: FlixShortcutCombo(keyCode: space, modifiers: [.option]))
        #expect(spotlight == .spotlight && spotlight?.refuses == false)
        #expect(launcher == .launcher && launcher?.refuses == false)
    }

    @Test func combinationsRoundTripThroughJSON() throws {
        let combo = FlixShortcutCombo(keyCode: UInt16(kVK_ANSI_J), modifiers: [.control, .shift])
        #expect(try JSONDecoder().decode(FlixShortcutCombo.self, from: JSONEncoder().encode(combo)) == combo)
    }

    @MainActor @Test func keysWithoutACharacterHaveFixedNames() {
        #expect(FlixShortcutCombo.keyName(for: UInt16(kVK_Space)) == "Space")
        #expect(FlixShortcutCombo.keyName(for: UInt16(kVK_F12)) == "F12")
        #expect(FlixShortcutCombo(keyCode: UInt16(kVK_Return), modifiers: [.command]).displayString == "⌘↩")
    }
}
