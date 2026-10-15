import AppKit
import Foundation
import Testing
@testable import DeeDock

/// Onboarding's coordinator over an inert engine, a stub inspector and a downloader that never downloads: closing it
/// partway saves nothing, it reopens where it was left, and the first pass applies setup once.
@MainActor
struct LookoutSetupCoordinatorTests {
    private let home = "/Users/tester"

    private func coordinator(models: LookoutModelDownloader.FileState = .ready,
                             access: [String: LookoutFolderAccess] = [:]) -> (LookoutSetupCoordinator, Holds) {
        let holds = Holds()
        let setup = LookoutSetupCoordinator(
            engine: .inert(), downloader: .inert(state: models),
            inspector: LookoutStubFolderInspector(accessByPath: access), picker: LookoutStubFolderPicker(), home: home)
        setup.holdHub = { holds.count += $0 ? 1 : -1 }
        return (setup, holds)
    }

    final class Holds { var count = 0 }

    @Test("Presenting holds the Hub open, and closing releases it")
    func holdsTheHub() {
        let (setup, holds) = coordinator()
        setup.present()
        #expect(setup.isPresented && holds.count == 1)
        setup.close()
        #expect(!setup.isPresented && holds.count == 0)
        setup.hubDidClose()
        #expect(holds.count == 0, "a second end releases nothing")
    }

    @Test("Closing partway saves nothing, and opening again resumes at the same step")
    func abandonAndResume() async {
        let (setup, _) = coordinator()
        setup.present()
        setup.continueStep()
        #expect(setup.draft.step == .folders)
        setup.continueStep()
        #expect(setup.draft.step == .access)
        setup.requestAccess(home + "/Desktop")
        #expect(await eventually { setup.draft.folder(home + "/Desktop")?.access == .allowed })
        setup.close()
        #expect(setup.engine.settings == LookoutSettings(), "nothing half-configured")
        #expect(setup.engine.status == .notSetUp)
        setup.present()
        #expect(setup.isPresented && setup.draft.step == .access)
        #expect(setup.draft.folder(home + "/Desktop")?.access == .allowed, "the draft survives")
    }

    @Test("The first pass applies setup with the allowed folders; its buttons only end onboarding")
    func firstPassCommits() async {
        let (setup, holds) = coordinator(access: [home + "/Documents": .denied])
        setup.present()
        setup.continueStep()   // folders
        setup.continueStep()   // access
        for folder in setup.draft.chosen { setup.requestAccess(folder.path) }
        #expect(await eventually { setup.draft.chosen.allSatisfy(\.access.isSettled) })
        setup.setIndexOnBattery(false)
        setup.continueStep()   // download
        #expect(setup.draft.step == .download)
        setup.continueStep()   // first pass
        #expect(setup.draft.step == .firstPass)
        let settings = setup.engine.settings
        #expect(settings.setupCompleted && settings.enabled && !settings.indexOnBattery)
        #expect(settings.folders == [home + "/Desktop", home + "/Downloads"])
        setup.finish(startSearching: false)
        #expect(!setup.isPresented && holds.count == 0)
        #expect(setup.draft.step == .welcome, "a finished draft starts over")
        setup.present()
        #expect(!setup.isPresented, "set up already")
    }

    @Test("The download step waits for the model")
    func downloadGate() async {
        let (setup, _) = coordinator(models: .waiting)
        setup.present()
        setup.continueStep()
        setup.continueStep()
        for folder in setup.draft.chosen { setup.requestAccess(folder.path) }
        #expect(await eventually { setup.draft.chosen.allSatisfy(\.access.isSettled) })
        setup.continueStep()
        #expect(setup.draft.step == .download && !setup.canContinue)
        setup.continueStep()
        #expect(setup.draft.step == .download)
        #expect(setup.engine.settings == LookoutSettings())
    }

    @Test("Return continues, Escape closes, and the Hub's tab shortcuts wait")
    func keyboard() throws {
        let (setup, _) = coordinator()
        setup.present()
        #expect(setup.handleKeyDown(try key("\r", code: 36)))
        #expect(setup.draft.step == .folders)
        #expect(setup.handleKeyDown(try key("2", code: 19, modifiers: .command)))
        #expect(setup.draft.step == .folders)
        #expect(!setup.handleKeyDown(try key("\t", code: 48)))
        #expect(setup.handleKeyDown(try key("\u{1b}", code: 53)))
        #expect(!setup.isPresented)
    }

    private func key(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                                      windowNumber: 0, context: nil, characters: characters,
                                      charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
    }
}
