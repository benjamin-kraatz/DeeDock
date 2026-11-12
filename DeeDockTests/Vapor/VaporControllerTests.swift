import Foundation
import Testing
@testable import DeeDock

/// Vapor's state machine with the real staging engine on temporary folders, a hand-fired clock,
/// an inert preferences store and recorded analytics.
@MainActor
struct VaporControllerTests {
    private final class Recorder {
        var events: [VaporAnalyticsEvent] = []
    }

    private struct Fixture {
        let temp: VaporTempDirectory
        let home: URL
        let store: VaporStore
        let sleeper = VaporManualSleeper()
        let recorder = Recorder()
        let engine: VaporDeletionEngine
        let controller: VaporController

        init(measurer: any VaporMeasuring = VaporFixedMeasurer(), now: @escaping () -> Date = Date.init) throws {
            temp = try VaporTempDirectory("vapor-controller")
            home = temp.url.appendingPathComponent("home", isDirectory: true)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            store = VaporStore(defaults: nil)
            engine = VaporDeletionEngine(
                ledger: VaporLedgerFile(url: temp.url.appendingPathComponent("ledger.json")),
                location: VaporStagingLocation(homeStaging: temp.url.appendingPathComponent("staging", isDirectory: true)))
            let recorder = recorder
            // Temporary folders live under /private/var, a protected location, so the system list is
            // emptied here. Protection itself is covered by VaporDropPolicyTests.
            controller = VaporController(dependencies: .init(
                store: store, home: home, policy: VaporDropPolicy(home: home, systemRoots: []),
                measurer: measurer, deleter: engine, now: now, sleep: sleeper.sleep,
                analytics: { recorder.events.append($0) }))
        }

        func folder(_ path: String) throws -> URL {
            let url = try temp.folder("home/\(path)")
            try temp.file("home/\(path)/a/file.bin", bytes: 128)
            return url
        }
    }

    private func paths(_ controller: VaporController) -> [String] { controller.folders.map(\.url.path) }

    @Test func addingMeasuresClassifiesPersistsAndAnnounces() async throws {
        let fixture = try Fixture()
        let modules = try fixture.folder("dev/app/node_modules")
        let other = try fixture.folder("dev/app/stuff")
        #expect(fixture.controller.add([modules, other], source: .drop))
        #expect(paths(fixture.controller) == [modules.path, other.path])
        #expect(fixture.controller.folders.map(\.classification) == [.known(.npmPackages), .unknown])
        #expect(fixture.controller.unknownCount == 1)
        #expect(fixture.controller.addition?.payload.folderIDs == fixture.controller.folders.map(\.id))
        #expect(fixture.store.state.folderPaths == [modules.path, other.path])
        #expect(fixture.recorder.events == [.foldersAdded(source: .drop, count: 2)])
        await vaporSettle { !fixture.controller.totals.isPending }
        #expect(fixture.controller.totals == VaporTotals(count: 2, bytes: 2_000, files: 6, isPending: false))
    }

    @Test func refusalsRaiseAnEventThatClearsItself() async throws {
        let fixture = try Fixture()
        let file = try fixture.temp.file("home/notes.txt")
        #expect(!fixture.controller.add([file], source: .drop))
        #expect(fixture.controller.refusal?.payload == .notAFolder)
        #expect(fixture.controller.callout == .refusal(.notAFolder))
        #expect(fixture.recorder.events.isEmpty)
        let documents = try fixture.temp.folder("home/Documents")
        fixture.controller.add([documents], source: .drop)
        #expect(fixture.controller.refusal?.payload == .standardFolder(name: "Documents"))
        await vaporSettle { fixture.sleeper.pending == [VaporController.refusalDuration] }
        fixture.sleeper.fire(VaporController.refusalDuration)
        await vaporSettle { fixture.controller.refusal == nil }
        #expect(fixture.controller.refusal == nil)
    }

    @Test func aParentReplacesContainedFoldersAndNestedOnesAreRefused() throws {
        let fixture = try Fixture()
        let app = try fixture.folder("dev/app")
        let modules = try fixture.folder("dev/app/node_modules")
        let next = try fixture.folder("dev/app/.next")
        fixture.controller.add([modules, next], source: .drop)
        fixture.controller.add([app], source: .drop)
        #expect(paths(fixture.controller) == [app.path])
        fixture.controller.add([modules], source: .suggestion)
        #expect(fixture.controller.refusal?.payload == .alreadyAdded(name: "node_modules"))
        #expect(paths(fixture.controller) == [app.path])
    }

    @Test func removeAndClearNeverTouchTheDisk() throws {
        let fixture = try Fixture()
        let a = try fixture.folder("a/node_modules")
        let b = try fixture.folder("b/node_modules")
        fixture.controller.add([a, b], source: .drop)
        fixture.controller.remove((try #require(fixture.controller.folders.first)).id)
        #expect(paths(fixture.controller) == [b.path])
        fixture.controller.clear()
        #expect(fixture.controller.folders.isEmpty)
        #expect(fixture.store.state.folderPaths.isEmpty)
        #expect(fixture.temp.exists(a) && fixture.temp.exists(b))
    }

    @Test func savedFoldersComeBackAndMissingOnesAreDropped() async throws {
        let fixture = try Fixture()
        let a = try fixture.folder("a/node_modules")
        let b = try fixture.folder("b/target")
        fixture.store.setFolders([a, b])
        try FileManager.default.removeItem(at: b)
        fixture.controller.start()
        #expect(paths(fixture.controller) == [a.path])
        #expect(fixture.controller.addition == nil)
        #expect(fixture.recorder.events.isEmpty)
    }

    @Test func deleteStagesOpensTheUndoWindowThenFreesAndRemoves() async throws {
        let clock = Date(timeIntervalSinceReferenceDate: 10_000)
        let fixture = try Fixture(now: { clock })
        let a = try fixture.folder("a/node_modules")
        let b = try fixture.folder("b/.next")
        fixture.controller.add([a, b], source: .drop)
        await vaporSettle { !fixture.controller.totals.isPending }
        fixture.controller.openPanel()
        let staging = fixture.controller.deleteAll()
        #expect(fixture.controller.isStaging)
        #expect(!fixture.controller.isPanelOpen)
        #expect(fixture.controller.deletion?.payload.folderIDs.count == 2)
        await staging?.value
        #expect(!fixture.controller.isStaging)
        #expect(fixture.controller.folders.isEmpty)
        #expect(!fixture.temp.exists(a) && !fixture.temp.exists(b))
        #expect(fixture.controller.status?.kind == .deleted(count: 2, failed: 0, deadline: clock.addingTimeInterval(5)))
        #expect(fixture.controller.undoDeadline == clock.addingTimeInterval(5))
        #expect(fixture.recorder.events.last == .deleted(count: 2, bytes: 2_000))
        #expect(await fixture.engine.ledgerEntries().count == 2)

        await vaporSettle { fixture.sleeper.pending.contains(VaporController.undoWindow) }
        fixture.sleeper.fire(VaporController.undoWindow)
        await vaporSettle { fixture.controller.status?.kind == .freed(bytes: 2_000, count: 2, failed: 0) }
        #expect(fixture.controller.status?.kind == .freed(bytes: 2_000, count: 2, failed: 0))
        for task in fixture.controller.removalTasks { await task.value }
        #expect(await fixture.engine.ledgerEntries().isEmpty)
        let staged = try FileManager.default.contentsOfDirectory(atPath: fixture.temp.url.appendingPathComponent("staging").path)
        #expect(staged.isEmpty)

        await vaporSettle { fixture.sleeper.pending.contains(VaporController.freedDuration) }
        fixture.sleeper.fire(VaporController.freedDuration)
        await vaporSettle { fixture.controller.status == nil }
        #expect(fixture.controller.status == nil)
    }

    @Test func undoPutsFoldersBackIntoTheOrb() async throws {
        let fixture = try Fixture()
        let a = try fixture.folder("a/node_modules")
        fixture.controller.add([a], source: .drop)
        await vaporSettle { !fixture.controller.totals.isPending }
        let id = (try #require(fixture.controller.folders.first)).id
        await fixture.controller.deleteAll()?.value
        #expect(!fixture.temp.exists(a))
        let deleted = try #require(fixture.controller.status)
        await fixture.controller.undo()?.value
        #expect(fixture.temp.exists(a.appendingPathComponent("a/file.bin")))
        #expect(fixture.controller.folders.map(\.id) == [id])
        #expect((try #require(fixture.controller.folders.first)).measurement == .measured(bytes: 1_000, files: 3))
        // "Put back 1 folder" replaces "Deleted 1 folder" in the same capsule.
        #expect(fixture.controller.status?.kind == .restored(count: 1))
        #expect(fixture.controller.status?.token == deleted.token)
        #expect(fixture.controller.addition?.payload.source == .restore)
        #expect(fixture.recorder.events.last == .undone(count: 1))
        #expect(await fixture.engine.ledgerEntries().isEmpty)
        // The undo window's timer no longer does anything.
        fixture.sleeper.fire(VaporController.undoWindow)
        await Task.yield()
        #expect(fixture.controller.status?.kind == .restored(count: 1))
        #expect(fixture.controller.undo() == nil)
        await vaporSettle { fixture.sleeper.pending.contains(VaporController.restoredDuration) }
        fixture.sleeper.fire(VaporController.restoredDuration)
        await vaporSettle { fixture.controller.status == nil }
        #expect(fixture.controller.status == nil)
    }

    @Test func undoLeavesAFolderStagedWhenItsPlaceIsTaken() async throws {
        let fixture = try Fixture()
        let a = try fixture.folder("a/node_modules")
        let b = try fixture.folder("b/node_modules")
        fixture.controller.add([a, b], source: .drop)
        await fixture.controller.deleteAll()?.value
        let replacement = try fixture.temp.file("home/a/node_modules/fresh.txt")
        await fixture.controller.undo()?.value
        #expect(paths(fixture.controller) == [b.path])
        #expect(fixture.controller.status?.kind == .notRestored(count: 1))
        #expect(fixture.temp.exists(replacement))
        for task in fixture.controller.removalTasks { await task.value }
        #expect(await fixture.engine.ledgerEntries().isEmpty)
        #expect(fixture.temp.exists(replacement))
    }

    @Test func aFolderThatCantBeStagedStaysWithItsReason() async throws {
        let fixture = try Fixture()
        let a = try fixture.folder("a/node_modules")
        let b = try fixture.folder("b/node_modules")
        fixture.controller.add([a, b], source: .drop)
        try FileManager.default.removeItem(at: b)
        await fixture.controller.deleteAll()?.value
        #expect(paths(fixture.controller) == [b.path])
        #expect((try #require(fixture.controller.folders.first)).failure == .missing)
        #expect(fixture.controller.status?.kind == .deleted(count: 1, failed: 1,
                                                            deadline: fixture.controller.undoDeadline ?? .distantPast))
        // When nothing can be staged, the capsule says so.
        let only = try Fixture()
        let gone = try only.folder("c/node_modules")
        only.controller.add([gone], source: .drop)
        try FileManager.default.removeItem(at: gone)
        await only.controller.deleteAll()?.value
        #expect(only.controller.status?.kind == .failed(count: 1))
        #expect(only.controller.folders.count == 1)
        #expect(!only.recorder.events.contains { if case .deleted = $0 { true } else { false } })
    }

    @Test func aFolderSwappedForALinkAfterAddingIsLeftAlone() async throws {
        let fixture = try Fixture()
        let folder = try fixture.folder("dev/app/node_modules")
        let keep = try fixture.temp.file("home/precious/keep.txt")
        fixture.controller.add([folder], source: .drop)
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: keep.deletingLastPathComponent())
        await fixture.controller.deleteAll()?.value
        #expect(paths(fixture.controller) == [folder.path])
        #expect((try #require(fixture.controller.folders.first)).failure == .changed)
        #expect(fixture.controller.status?.kind == .failed(count: 1))
        #expect(fixture.temp.exists(keep))
        #expect(await fixture.engine.ledgerEntries().isEmpty)
    }

    @Test func aSecondDeleteCommitsTheFirstUndoWindow() async throws {
        let fixture = try Fixture()
        let a = try fixture.folder("a/node_modules")
        fixture.controller.add([a], source: .drop)
        await fixture.controller.deleteAll()?.value
        let b = try fixture.folder("b/node_modules")
        fixture.controller.add([b], source: .drop)
        await fixture.controller.deleteAll()?.value
        for task in fixture.controller.removalTasks { await task.value }
        // Only the second folder is still staged and undoable.
        #expect(await fixture.engine.ledgerEntries().map(\.originalPath) == [b.path])
        await fixture.controller.undo()?.value
        #expect(paths(fixture.controller) == [b.path])
        #expect(!fixture.temp.exists(a))
    }

    @Test func hidingTheOrbClosesThePanelAndHidesBubblesUntilShownAgain() throws {
        let fixture = try Fixture()
        let project = try fixture.folder("dev/web")
        let next = try fixture.folder("dev/web/.next")
        let controller = fixture.controller
        controller.setFinderFolder(project, items: [VaporSuggestion(url: next, tag: .nextBuild)])
        controller.isOrbHovered = true
        controller.openPanel()
        controller.closePanel()
        #expect(controller.bubbleSuggestions.count == 1 && controller.callout != nil)
        #expect(!controller.orbPresence.isEntering)

        controller.openPanel()
        controller.hideOrb()
        #expect(!controller.isPanelOpen && !controller.orbPresence.isShown && controller.orbPresence.token != nil)
        #expect(controller.bubbleSuggestions.isEmpty && controller.callout == nil)
        controller.openPanel()
        #expect(!controller.isPanelOpen)

        controller.showOrb(animated: true)
        #expect(controller.orbPresence.isEntering)
        #expect(controller.bubbleSuggestions.count == 1)
    }

    @Test func stoppingCommitsAPendingDeleteAndKeepsFolders() async throws {
        let fixture = try Fixture()
        let a = try fixture.folder("a/node_modules")
        let kept = try fixture.folder("b/other")
        fixture.controller.add([a], source: .drop)
        await fixture.controller.deleteAll()?.value
        fixture.controller.add([kept], source: .drop)
        fixture.controller.stop()
        #expect(fixture.controller.status == nil)
        #expect(paths(fixture.controller) == [kept.path])
        for task in fixture.controller.removalTasks { await task.value }
        #expect(await fixture.engine.ledgerEntries().isEmpty)
        #expect(fixture.controller.undo() == nil)
    }

    @Test func completingTheHoldDeletesAndReleasingDoesNot() async throws {
        let fixture = try Fixture()
        let a = try fixture.folder("a/node_modules")
        fixture.controller.add([a], source: .drop)
        fixture.controller.pressHold()
        #expect(fixture.controller.hold.isHolding)
        fixture.controller.releaseHold()
        #expect(!fixture.controller.hold.isHolding)
        // The released hold's timer was cancelled, so firing does nothing.
        fixture.sleeper.fire(.seconds(VaporHoldProgress.holdDuration))
        await Task.yield()
        #expect(fixture.temp.exists(a))
        let fresh = try Fixture()
        let b = try fresh.folder("b/node_modules")
        fresh.controller.add([b], source: .drop)
        fresh.controller.pressHold()
        await vaporSettle { fresh.sleeper.pending.count == 1 }
        try #require(fresh.sleeper.pending.count == 1)
        fresh.sleeper.fire(fresh.sleeper.pending[0])
        await vaporSettle { fresh.controller.status != nil }
        #expect(!fresh.temp.exists(b))
        #expect(fresh.controller.hold.progress(at: .now) == 0)
    }

    @Test func suggestionsExcludeWhatIsInTheOrbAndRespectDismissal() throws {
        let fixture = try Fixture()
        let project = try fixture.folder("dev/web")
        let modules = try fixture.folder("dev/web/node_modules")
        let next = try fixture.folder("dev/web/.next")
        let items = [VaporSuggestion(url: next, tag: .nextBuild), VaporSuggestion(url: modules, tag: .npmPackages)]
        let controller = fixture.controller
        controller.setFinderFolder(project, items: items)
        #expect(controller.suggestions.map(\.name) == [".next", "node_modules"])
        controller.addSuggestion(items[1])
        #expect(controller.suggestions.map(\.name) == [".next"])
        #expect(fixture.recorder.events.last == .foldersAdded(source: .suggestion, count: 1))
        controller.openPanel()
        #expect(controller.bubbleSuggestions.isEmpty)
        #expect(controller.suggestions.count == 1)
        controller.closePanel()
        controller.dismissSuggestions()
        #expect(controller.suggestions.isEmpty)
        // Same folder again: still dismissed. A different folder clears the dismissal.
        controller.setFinderFolder(project, items: items)
        #expect(controller.suggestions.isEmpty)
        controller.setFinderFolder(modules, items: [])
        controller.setFinderFolder(project, items: items)
        #expect(controller.suggestions.map(\.name) == [".next"])
        controller.addAllSuggestions()
        #expect(controller.suggestions.isEmpty)
        #expect(fixture.recorder.events.last == .foldersAdded(source: .addAll, count: 1))
        controller.clearFinderFolder()
        #expect(controller.finderFolder == nil && controller.bubbleSuggestions.isEmpty)
    }

    @Test func calloutPriorityAndTooltip() throws {
        let fixture = try Fixture(measurer: VaporStalledMeasurer())
        let controller = fixture.controller
        #expect(controller.callout == nil)
        controller.isOrbHovered = true
        #expect(controller.callout == .tooltip(.empty))
        controller.add([try fixture.folder("a/node_modules")], source: .drop)
        #expect(controller.callout == .tooltip(VaporTotals(count: 1, bytes: 0, files: 0, isPending: true)))
        controller.dropHover = VaporDropHover(proximity: VaporDropProximity(value: 1, isOverOrb: true, lean: .zero))
        #expect(controller.callout == .dropToAdd)
        controller.add([try fixture.temp.file("home/x.txt")], source: .drop)
        #expect(controller.callout == .refusal(.notAFolder))
        controller.stop()
        #expect(controller.callout == nil)
    }

    @Test func analyticsEventsMapToCountOnlyEvents() {
        #expect(AnalyticsEvent.vapor(.foldersAdded(source: .restore, count: 3)) == nil)
        #expect(AnalyticsVaporSizeBucket(bytes: 0) == .unknown)
        #expect(AnalyticsVaporSizeBucket(bytes: 99_000_000) == .under100MB)
        #expect(AnalyticsVaporSizeBucket(bytes: 1_800_000_000) == .under10GB)
        #expect(AnalyticsVaporSizeBucket(bytes: 40_000_000_000) == .over10GB)
        #expect(AnalyticsEvent.vapor(.deleted(count: 2, bytes: 500_000_000))?.name == "vapor_deleted")
        #expect(AnalyticsEvent.vapor(.foldersAdded(source: .addAll, count: 2))?.name == "vapor_folders_added")
        #expect(AnalyticsEvent.vapor(.undone(count: 1))?.name == "vapor_undo")
        #expect(AnalyticsEvent.vaporToggled(enabled: true).name == "vapor_toggled")
    }

    @Test func storePersistsAcrossInstances() throws {
        let suite = "vapor-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = VaporStore(defaults: defaults)
        store.setEnabled(true)
        store.setPlacement(VaporOrbPlacement(x: 0.2, y: 0.8), displayID: "display.A")
        store.setFolders([URL(fileURLWithPath: "/tmp/x/node_modules")])
        let reloaded = VaporStore(defaults: defaults)
        #expect(reloaded.state == store.state)
        #expect(reloaded.isEnabled)
        #expect(reloaded.state.displayID == "display.A")
        store.setEnabled(false)
        #expect(VaporStore(defaults: defaults).state.folderPaths == ["/tmp/x/node_modules"])
    }
}
