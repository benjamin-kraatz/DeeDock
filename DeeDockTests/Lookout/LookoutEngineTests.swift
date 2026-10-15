import Foundation
import Testing
@testable import DeeDock

/// `LookoutEngine` over fakes: when it starts, what it sends the index service, how service statuses become UI
/// statuses, and what wakes the service after it exits.
@MainActor struct LookoutEngineTests {
    private let connection = FakeIndexConnection()
    private let encoder = FakeQueryEncoder()
    private let reader = FakeIndexReader()
    private let monitor = FakeMonitor()
    private let power = FakePowerPolicy()

    private func engine(_ settings: LookoutSettings = .activeForTests, canRun: Bool = true) -> LookoutEngine {
        LookoutEngine(settings: settings, repository: nil, connection: connection, encoder: encoder, reader: reader,
                      monitor: monitor, power: power,
                      paths: LookoutPaths(base: URL(fileURLWithPath: "/tmp/lookout-engine-tests", isDirectory: true)),
                      canRun: canRun, syncDebounce: .milliseconds(30), releaseDelay: .milliseconds(60))
    }

    private func status(_ activity: LookoutIndexStatus.Activity, pending: Int = 0, unfinished: Int = 0,
                        done: Int = 0, total: Int = 0) -> LookoutIndexStatus {
        var status = LookoutIndexStatus()
        status.activity = activity
        status.counts = IndexStore.Counts(byKindAndState: ["doc": ["pending": pending, "done": 3]], unfinished: unfinished)
        (status.done, status.total) = (done, total)
        return status
    }

    // MARK: Starting

    @Test func lookoutDoesNothingUntilItIsSetUpAndOn() {
        let notSetUp = engine(LookoutSettings())
        notSetUp.start()
        #expect(notSetUp.status == .notSetUp && !notSetUp.isRunning)
        var off = LookoutSettings.activeForTests
        off.enabled = false
        let turnedOff = engine(off)
        turnedOff.start()
        #expect(turnedOff.status == .off)
        let inert = engine(canRun: false)
        inert.start()
        #expect(!inert.isRunning)
        #expect(connection.calls.isEmpty && monitor.startedRoots == nil && power.indexOnBattery == nil)
    }

    @Test func startSendsTheFullRootListAndWatchesIt() throws {
        var settings = LookoutSettings.activeForTests
        settings.folders = ["/a", "/a/b", "/c"]
        settings.excludedFolders = ["/a/skip", "/z/skip"]
        settings.excludedExtensions = ["heic"]
        settings.indexOnBattery = false
        power.blocker = .onBattery
        let engine = engine(settings)
        engine.start()
        let configuration = try #require(connection.configurations.first)
        #expect(configuration.roots == ["/a", "/c"])   // /a/b is inside /a
        #expect(configuration.excludedFolders == ["/a/skip"])   // /z/skip leaves nothing out
        #expect(configuration.excludedExtensions == ["heic"])
        #expect(configuration.backfillAllowed == false)
        #expect(configuration.indexFolder == "/tmp/lookout-engine-tests")
        #expect(monitor.startedRoots == ["/a", "/c"] && power.indexOnBattery == false)
        #expect(engine.isRunning && engine.search.isAvailable)
        #expect(engine.status == .indexing(remaining: nil, progress: nil))
    }

    // MARK: Status

    @Test func serviceStatusesBecomeUIStatuses() {
        let engine = engine()
        engine.start()
        connection.send(status(.syncing, pending: 5))
        #expect(engine.status == .indexing(remaining: 5, progress: nil))
        connection.send(status(.indexing, pending: 7, done: 3, total: 10))
        #expect(engine.status == .indexing(remaining: 7, progress: 0.3))
        connection.send(status(.finishingLongFiles, unfinished: 2, done: 1, total: 4))
        #expect(engine.status == .indexing(remaining: 2, progress: 0.25))
        connection.send(status(.idle))
        #expect(engine.status == .ready)
        connection.send(status(.waitingForModel, pending: 9))
        #expect(engine.status == .waitingForModel)
        connection.send(status(.paused))
        #expect(engine.status == .paused(.user))
        connection.send(status(.failed(message: "can't open the index: disk full")))
        #expect(engine.status == .failed(LookoutFailure(kind: .index, detail: "can't open the index: disk full")))
        connection.send(status(.failed(message: "the model can't load")))
        if case .failed(let failure) = engine.status {
            #expect(failure.kind == .indexing && !failure.message.isEmpty)
        } else {
            Issue.record("expected a failure, got \(engine.status)")
        }
    }

    @Test func idleWithFilesWaitingSaysWhyTheBackfillWaits() {
        let engine = engine()
        engine.start()
        power.emit(.lowPowerMode)
        connection.send(status(.idle, pending: 4))
        #expect(engine.status == .paused(.lowPowerMode))
        power.emit(.warm)
        #expect(engine.status == .paused(.warm))
        power.emit(nil)
        #expect(engine.status == .ready)
    }

    @Test func missingAndUnreadableFoldersAreExposed() {
        let engine = engine()
        engine.start()
        var report = status(.idle)
        report.missingRoots = ["/Volumes/Drive/Photos"]
        report.notPermittedRoots = ["/Users/x/Desktop"]
        connection.send(report)
        #expect(engine.missingFolders == ["/Volumes/Drive/Photos"])
        #expect(engine.notPermittedFolders == ["/Users/x/Desktop"])
    }

    @Test func statusMappingPrecedence() {
        let active = LookoutSettings.activeForTests
        let idleWaiting = status(.idle, pending: 2)
        #expect(LookoutStatus.map(settings: LookoutSettings(), index: idleWaiting, blocker: .warm, userPaused: true,
                                  serviceUnavailable: true) == .notSetUp)
        #expect(LookoutStatus.map(settings: active, index: idleWaiting, blocker: .warm, userPaused: true,
                                  serviceUnavailable: true) == .paused(.user))
        #expect(LookoutStatus.map(settings: active, index: idleWaiting, blocker: .warm, userPaused: false,
                                  serviceUnavailable: true) == .failed(LookoutFailure(kind: .service)))
        #expect(LookoutStatus.map(settings: active, index: idleWaiting, blocker: .onBattery, userPaused: false,
                                  serviceUnavailable: false) == .paused(.onBattery))
        #expect(LookoutStatus.map(settings: active, index: nil, blocker: nil, userPaused: false,
                                  serviceUnavailable: false) == .indexing(remaining: nil, progress: nil))
    }

    // MARK: Waking the service

    @Test func folderChangesAreDebouncedIntoOneSync() async {
        let engine = engine()
        engine.start()
        connection.clearCalls()
        monitor.emit(.foldersChanged)
        monitor.emit(.foldersChanged)
        monitor.emit(.foldersChanged)
        #expect(connection.calls.isEmpty)
        #expect(await eventually { connection.calls == [.syncNow] })
        try? await Task.sleep(for: .milliseconds(80))
        #expect(connection.calls == [.syncNow])
        _ = engine
    }

    @Test func drivesWakeAndTheModelSyncAtOnce() {
        var settings = LookoutSettings.activeForTests
        settings.folders = ["/Volumes/Drive/Photos"]
        let engine = engine(settings)
        engine.start()
        connection.clearCalls()
        monitor.emit(.volumesChanged)
        #expect(monitor.watched == [["/Volumes/Drive/Photos"]] && connection.calls == [.syncNow])
        monitor.emit(.didWake)
        engine.modelDidArrive()
        #expect(connection.calls == [.syncNow, .syncNow, .syncNow])
    }

    @Test func theBackfillBecomingAllowedWakesAServiceThatExited() {
        let engine = engine()
        engine.start()
        power.emit(.onBattery)
        connection.send(status(.idle, pending: 3))
        connection.interrupt()   // it exited, idle, with the backfill waiting
        connection.clearCalls()
        power.emit(nil)
        #expect(connection.calls == [.setBackfillAllowed(true), .syncNow])
        connection.clearCalls()
        power.emit(.warm)
        power.emit(nil)   // running now: told, not relaunched
        #expect(connection.calls == [.setBackfillAllowed(false), .setBackfillAllowed(true)])
        #expect(engine.status == .ready)
    }

    @Test func anInterruptionMidWorkRelaunchesNothingAndClearsTheStaleActivity() {
        let engine = engine()
        engine.start()
        connection.send(status(.indexing, pending: 1, done: 1, total: 2))
        connection.clearCalls()
        connection.interrupt()
        #expect(connection.calls.isEmpty)
        #expect(engine.indexStatus?.activity == .idle && engine.status == .ready)
        monitor.emit(.didWake)   // the next reason to work relaunches it
        #expect(connection.calls == [.syncNow])
    }

    @Test func pauseAndResumeReachTheService() {
        let engine = engine()
        engine.start()
        connection.clearCalls()
        engine.pause()
        #expect(connection.calls == [.pause] && engine.status == .paused(.user))
        engine.resume()
        #expect(connection.calls == [.pause, .resume] && engine.status == .indexing(remaining: nil, progress: nil))
    }

    @Test func aPauseBeforeStartIsSentBeforeTheConfiguration() {
        let engine = engine()
        engine.pause()
        #expect(connection.calls.isEmpty)
        engine.start()
        #expect(connection.calls.first == .pause && connection.configurations.count == 1)
    }

    // MARK: Settings

    @Test func newFoldersRestartTheServiceAndTheWatcher() {
        let engine = engine()
        engine.start()
        connection.clearCalls()
        var settings = engine.settings
        settings.folders = ["/new"]
        engine.apply(settings)
        #expect(connection.configurations.map(\.roots) == [["/new"]])
        #expect(monitor.watched == [["/new"]])
        settings.indexOnBattery = false
        engine.apply(settings)
        #expect(power.indexOnBattery == false && connection.configurations.count == 1)
    }

    @Test func turningLookoutOffStopsEverythingAndOnStartsIt() async {
        let engine = engine()
        engine.start()
        var settings = engine.settings
        settings.enabled = false
        engine.apply(settings)
        #expect(connection.calls.last == .invalidate && monitor.stopped == 1)
        #expect(!engine.isRunning && engine.status == .off && !engine.search.isAvailable)
        #expect(await eventually { await reader.released == 1 })
        settings.enabled = true
        engine.apply(settings)
        #expect(engine.isRunning && connection.configurations.count == 2)
    }

    // MARK: Memory

    @Test func theFilesTabWarmsTheEncoderAndLoadsTheVectors() async {
        encoder.isWarm = false
        let engine = engine()
        engine.start()
        engine.hubFilesDidAppear()
        #expect(await eventually { encoder.warmUps == 1 })
        #expect(await eventually { await reader.prepared == 1 })
    }

    @Test func vectorsLeaveAfterTheDelayUnlessTheTabComesBack() async {
        let engine = engine()
        engine.start()
        engine.hubDidClose()
        engine.hubFilesDidAppear()   // back before the delay: nothing is released
        try? await Task.sleep(for: .milliseconds(150))
        #expect(await reader.released == 0)
        engine.hubDidClose()
        #expect(await eventually { await reader.released == 1 })
    }

    @Test func changedVectorsReachTheReaderOnce() async {
        let engine = engine()
        engine.start()
        var changed = status(.indexing)
        changed.vectorsChangedAt = Date(timeIntervalSince1970: 100)
        connection.send(changed)
        connection.send(changed)   // the same change again
        #expect(await eventually { await reader.changes == 1 })
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await reader.changes == 1)
        changed.vectorsChangedAt = Date(timeIntervalSince1970: 200)
        connection.send(changed)
        #expect(await eventually { await reader.changes == 2 })
    }
}

extension LookoutSettings {
    /// Set up and on, with one folder.
    nonisolated static var activeForTests: LookoutSettings {
        var settings = LookoutSettings()
        settings.enabled = true
        settings.setupCompleted = true
        settings.folders = ["/Users/x/Documents"]
        return settings
    }
}
