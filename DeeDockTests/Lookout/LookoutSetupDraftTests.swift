import Foundation
import Testing
@testable import DeeDock

/// Onboarding's step rules over `LookoutSetupDraft`: when Continue is enabled, which step it leads to (the access
/// step is skipped when there's nothing to ask), where onboarding resumes, and what setup saves.
struct LookoutSetupDraftTests {
    private let home = "/Users/tester"

    private func draft(at step: LookoutSetupStep = .welcome) -> LookoutSetupDraft {
        var draft = LookoutSetupDraft(home: home)
        draft.step = step
        return draft
    }

    @Test("Desktop, Documents and Downloads are suggested and checked; Pictures is listed unchecked")
    func suggestions() {
        let draft = draft()
        #expect(draft.folders.map(\.path) == ["Desktop", "Documents", "Downloads", "Pictures"].map { home + "/" + $0 })
        #expect(draft.chosen.map(\.path) == ["Desktop", "Documents", "Downloads"].map { home + "/" + $0 })
        // Protected folders wait for the access step for their estimate; Pictures is estimated at once.
        #expect(draft.folders.map(\.estimate) == [.afterAccess, .afterAccess, .afterAccess, .estimating])
    }

    @Test("Continue on the folders step needs a chosen folder")
    func foldersNeedAChoice() {
        var draft = draft(at: .folders)
        #expect(draft.canContinue(modelsReady: false))
        for folder in draft.chosen { draft.setChosen(folder.path, false) }
        #expect(!draft.canContinue(modelsReady: false))
    }

    @Test("Continue on the access step needs every answer and at least one folder allowed")
    func accessNeedsAnswers() {
        var draft = draft(at: .access)
        #expect(!draft.canContinue(modelsReady: true))
        draft.setAccess(home + "/Desktop", .allowed)
        draft.setAccess(home + "/Documents", .checking)
        draft.setAccess(home + "/Downloads", .denied)
        #expect(!draft.canContinue(modelsReady: true))
        draft.setAccess(home + "/Documents", .missing)
        #expect(draft.canContinue(modelsReady: true))
        draft.setAccess(home + "/Desktop", .denied)
        #expect(!draft.canContinue(modelsReady: true), "nothing would be read")
    }

    @Test("Continue on the download step waits for both model files")
    func downloadNeedsTheModel() {
        var draft = draft(at: .download)
        draft.setAccess(home + "/Desktop", .allowed)
        #expect(!draft.canContinue(modelsReady: false))
        #expect(draft.canContinue(modelsReady: true))
    }

    @Test("The access step is skipped when every chosen folder is allowed already, both ways")
    func accessStepSkipped() {
        var draft = draft(at: .folders)
        #expect(draft.nextStep == .access)
        for folder in draft.chosen { draft.setChosen(folder.path, false) }
        draft.setChosen(home + "/Pictures", true)
        draft.setAccess(home + "/Pictures", .allowed)
        #expect(draft.nextStep == .download)
        draft.step = .download
        #expect(draft.previousStep == .folders)
    }

    @Test("A declined folder keeps the access step, so going back shows it")
    func declinedKeepsAccessStep() {
        var draft = draft(at: .download)
        draft.setAccess(home + "/Desktop", .allowed)
        draft.setAccess(home + "/Documents", .allowed)
        draft.setAccess(home + "/Downloads", .denied)
        #expect(draft.previousStep == .access)
    }

    @Test("The welcome and first-pass steps have no way back")
    func noWayBack() {
        #expect(draft(at: .welcome).previousStep == nil)
        #expect(draft(at: .firstPass).previousStep == nil)
        #expect(draft(at: .firstPass).nextStep == nil)
    }

    @Test("Onboarding resumes where it was left, unless an earlier step no longer holds")
    func resume() {
        #expect(draft(at: .folders).resumeStep == .folders)
        #expect(draft(at: .access).resumeStep == .access)
        var download = draft(at: .download)
        #expect(download.resumeStep == .access, "nothing allowed yet")
        download.setAccess(home + "/Desktop", .allowed)
        #expect(download.resumeStep == .download)
        for folder in download.chosen { download.setChosen(folder.path, false) }
        #expect(download.resumeStep == .folders)
    }

    @Test("Setup saves only chosen, allowed folders, the battery choice, and Lookout on")
    func settings() {
        var draft = draft(at: .download)
        draft.setAccess(home + "/Desktop", .allowed)
        draft.setAccess(home + "/Documents", .denied)
        draft.setAccess(home + "/Downloads", .allowed)
        draft.setAccess(home + "/Pictures", .allowed)   // allowed, but not chosen
        draft.indexOnBattery = false
        var base = LookoutSettings()
        base.excludedExtensions = ["heic"]
        let settings = draft.settings(from: base)
        #expect(settings.folders == [home + "/Desktop", home + "/Downloads"])
        #expect(settings.isActive && settings.setupCompleted && settings.enabled)
        #expect(settings.indexOnBattery == false)
        #expect(settings.excludedExtensions == ["heic"])
        #expect(draft.skipped.map(\.path) == [home + "/Documents"])
    }

    @Test("Totals add up known estimates and count folders still waiting for access")
    func totals() {
        var draft = draft(at: .folders)
        draft.setAccess(home + "/Desktop", .allowed)
        draft.setEstimate(home + "/Desktop", .ready(LookoutFolderEstimate(files: 400, seconds: 100, bytes: 10)))
        draft.setChosen(home + "/Pictures", true)
        draft.setEstimate(home + "/Pictures", .ready(LookoutFolderEstimate(files: 600, seconds: 30, bytes: 5)))
        let total = draft.total
        #expect(total.estimate == LookoutFolderEstimate(files: 1_000, seconds: 130, bytes: 15))
        #expect(total.pending == 2)   // Documents and Downloads
        #expect(total.estimate.minutes == 3)
    }

    @Test("Allowing a protected folder starts its estimate; declining it makes none")
    func accessDrivesEstimates() {
        var draft = draft(at: .access)
        draft.setAccess(home + "/Desktop", .allowed)
        draft.setAccess(home + "/Documents", .denied)
        #expect(draft.folder(home + "/Desktop")?.estimate == .estimating)
        #expect(draft.folder(home + "/Documents")?.estimate == .unavailable)
    }
}
