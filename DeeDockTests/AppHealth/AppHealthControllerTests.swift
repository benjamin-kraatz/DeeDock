import Foundation
import Testing
@testable import DeeDock

/// The collector's lifecycle with every service faked: no libproc, Accessibility, files, or real 20 s waits.
@MainActor
struct AppHealthControllerTests {
    private let busy = AppHealthWatchedApp(bundleID: "com.example.Busy", kind: .regular, pid: 100, bundlePath: nil)
    private let quiet = AppHealthWatchedApp(bundleID: "com.example.Quiet", kind: .accessory, pid: 200, bundlePath: nil)

    private func makeController(collecting: Bool = false, crashDelay: Duration = .seconds(3600))
        -> (AppHealthController, FakeAppHealthStore, FakeAppHealthSampler, FakeAppHealthObservers) {
        let store = FakeAppHealthStore()
        let sampler = FakeAppHealthSampler(usage: [
            busy.bundleID: AppHealthAppUsage(cpuMain: 10, mem: 400_000_000, memMain: 400_000_000, procs: 1),
            quiet.bundleID: AppHealthAppUsage(mem: 50_000_000, memMain: 50_000_000, procs: 1),
        ])
        let observers = FakeAppHealthObservers()
        let apps = [busy, quiet]
        let dependencies = AppHealthControllerDependencies(
            sampler: sampler, store: store, hangChecker: FakeAppHealthHangChecker(),
            crashReports: FakeAppHealthCrashReports(), observers: observers,
            snapshot: { date, power, thermal in
                AppHealthSystemSnapshot(date: date, apps: apps, frontmost: nil, idleSeconds: 0, power: power,
                                        thermal: thermal, accessibilityTrusted: false)
            },
            powerSource: { .ac }, thermalState: { .nominal },
            waitForNextTick: { try await Task.sleep(for: .milliseconds(5)) },
            crashReportDelay: { try await Task.sleep(for: crashDelay) },
            now: { Date() }, appVersion: { "test" })
        let controller = AppHealthController(
            settings: AppHealthSettingsStore(defaults: nil, initial: .init(collecting: collecting, labelling: false)),
            labelling: AppHealthLabellingPreferences(defaults: nil), dependencies: dependencies)
        return (controller, store, sampler, observers)
    }

    @Test("Collection off at launch starts nothing")
    func offAtLaunch() async throws {
        let (controller, store, sampler, observers) = makeController()
        controller.start()
        try await Task.sleep(for: .milliseconds(50))
        #expect(controller.phase == .off)
        #expect(!observers.isStarted)
        #expect(await sampler.sampleCount == 0)
        #expect(await store.events().isEmpty)
        controller.stop()
    }

    @Test("Turning collection on samples; turning it off stops sampling, observers, and writes")
    func onAndOff() async throws {
        let (controller, store, sampler, observers) = makeController()
        controller.start()
        controller.setCollecting(true)
        #expect(controller.phase == .collecting)
        #expect(observers.isStarted)
        #expect(await appHealthEventually { await store.count(type: "tick") >= 2 })
        #expect(await store.events().first == .collector(.collectorStart, reason: .enabled))
        // The first pass after a start is a baseline and writes no tick.
        #expect(await sampler.resetCount == 1)

        controller.setCollecting(false)
        #expect(controller.phase == .off)
        #expect(!observers.isStarted)
        #expect(controller.lastTick == nil)
        #expect(await appHealthEventually { await store.events().last == .collector(.collectorStop, reason: .disabled) })
        let samples = await sampler.sampleCount
        try await Task.sleep(for: .milliseconds(50))
        #expect(await sampler.sampleCount == samples)
        controller.writeEvent(AppHealthEventRecord(event: .resume))
        try await Task.sleep(for: .milliseconds(20))
        #expect(await store.events().last == .collector(.collectorStop, reason: .disabled))
        controller.stop()
    }

    @Test("Sleep pauses sampling; a display waking does not resume it; waking the Mac does, from a new baseline")
    func sleepAndWake() async throws {
        let (controller, store, sampler, observers) = makeController(collecting: true)
        controller.start()
        #expect(await appHealthEventually { await store.count(type: "tick") >= 1 })

        observers.send(.willSleep)
        observers.send(.screensDidSleep)
        #expect(controller.phase == .paused)
        let paused = await sampler.sampleCount
        observers.send(.screensDidWake)
        #expect(controller.phase == .paused)
        try await Task.sleep(for: .milliseconds(50))
        #expect(await sampler.sampleCount == paused)

        observers.send(.didWake)
        #expect(controller.phase == .collecting)
        #expect(await appHealthEventually { await sampler.resetCount == 2 })
        #expect(await appHealthEventually { await store.events().count >= 7 })
        let events = await store.events().filter { $0.event != .collectorStart || $0.reason != .enabled }
        #expect(Array(events.prefix(5)) == [
            AppHealthEventRecord(event: .sleep), .collector(.collectorStop, reason: .sleep),
            AppHealthEventRecord(event: .displaySleep), AppHealthEventRecord(event: .displayWake),
            AppHealthEventRecord(event: .wake),
        ])
        #expect(events.dropFirst(5).first == .collector(.collectorStart, reason: .sleep))
        controller.stop()
    }

    @Test("Stopping writes a pending termination without crashReport, after interrupted labels, before collectorStop")
    func flushesPendingWork() async throws {
        let (controller, store, _, observers) = makeController(collecting: true)
        let promptID = UUID()
        controller.willPause = { [weak controller] _ in
            controller?.writeLabel(AppHealthLabelRecord(id: promptID, app: "com.example.Busy", answer: .noAnswer,
                                                        from: .now, to: .now, source: .prompt, responseSeconds: 1,
                                                        interrupted: true))
        }
        controller.start()
        observers.send(.terminated(AppHealthAppIdentity(bundleID: "com.example.Busy", kind: .regular, pid: 100,
                                                        executableName: "Busy", launchDate: nil)))
        try await Task.sleep(for: .milliseconds(30))
        #expect(await store.events().contains { $0.event == .terminated } == false)

        controller.setCollecting(false)
        #expect(await appHealthEventually { await store.events().last?.event == .collectorStop })
        let types = await store.records.map(\.type).filter { $0 != "tick" && $0 != "sample" }
        let events = await store.events()
        let terminated = try #require(events.first { $0.event == .terminated })
        #expect(terminated.crashReport == nil)
        #expect(terminated.app == "com.example.Busy")
        #expect(Array(types.suffix(3)) == ["label", "event", "event"])
        #expect(events.suffix(2).map(\.event) == [.terminated, .collectorStop])
        controller.stop()
    }

    @Test("A finished crash-report lookup writes the termination with its answer")
    func crashReportLookup() async throws {
        let (controller, store, _, observers) = makeController(collecting: true, crashDelay: .milliseconds(1))
        controller.start()
        observers.send(.terminated(AppHealthAppIdentity(bundleID: "com.example.Busy", kind: .regular, pid: 100,
                                                        executableName: "Busy", launchDate: .now.addingTimeInterval(-90))))
        #expect(await appHealthEventually { await store.events().contains { $0.event == .terminated } })
        let terminated = try #require(await store.events().first { $0.event == .terminated })
        #expect(terminated.crashReport == true)
        #expect((terminated.runSeconds ?? 0) >= 90)
        controller.stop()
    }

    @Test("Backfill writes each unwritten tick of a window once")
    func backfillOnce() async throws {
        let (controller, store, _, _) = makeController(collecting: true)
        controller.start()
        #expect(await appHealthEventually { controller.history(for: "com.example.Quiet").count >= 4 })
        let unwritten = controller.history(for: "com.example.Quiet").filter { !$0.written }.count
        let written = controller.backfill(app: "com.example.Quiet", from: .distantPast, to: .distantFuture)
        #expect(written >= unwritten)
        #expect(written > 0)
        // Checked before any await, while no new tick can have arrived.
        let allWritten = controller.history(for: "com.example.Quiet").allSatisfy(\.written)
        #expect(allWritten)
        #expect(controller.backfill(app: "com.example.Quiet", from: .distantPast, to: .distantFuture) == 0)
        #expect(await appHealthEventually { await store.samples(why: .backfill) >= written })
        controller.stop()
    }

    @Test("Deleting while collecting drops the history and restarts sampling from a baseline after the deletion")
    func deleteIsACollectionBoundary() async throws {
        let (controller, store, sampler, _) = makeController(collecting: true)
        controller.start()
        #expect(await appHealthEventually { controller.history(for: "com.example.Busy").count >= 2 })
        controller.deleteAllData()
        // Checked before any await, so no tick can have refilled it.
        let history = controller.history(for: "com.example.Busy")
        #expect(history.isEmpty)
        #expect(controller.phase == .collecting)
        #expect(await appHealthEventually { await sampler.resetCount == 2 })
        #expect(await appHealthEventually { await store.count(type: "tick") >= 1 })
        // The new file begins with the restart, not with records from before the deletion.
        #expect(await store.events().first == .collector(.collectorStart, reason: .enabled))
        controller.stop()
    }

    @Test("Busy apps are written as active every tick; the tick hook carries every app")
    func tickHook() async throws {
        let (controller, store, _, _) = makeController(collecting: true)
        var reports: [AppHealthTickReport] = []
        controller.tickCompleted = { reports.append($0) }
        controller.start()
        #expect(await appHealthEventually { reports.count >= 3 })
        let everyAppReported = reports.allSatisfy { $0.samples.count == 2 }
        #expect(everyAppReported)
        #expect(reports.last?.samples["com.example.Busy"]?.cpuPercent == 50)
        #expect(await appHealthEventually { await store.samples(app: "com.example.Busy", why: .active) >= 3 })
        controller.stop()
    }
}

// MARK: - Fakes

private actor FakeAppHealthStore: AppHealthRecording {
    private(set) var records: [AppHealthRecord] = []

    func append(_ records: [AppHealthRecord]) { self.records += records }
    func summary() -> AppHealthStorageSummary { .empty }
    func deleteAll() throws { records.removeAll() }
    func export(to destination: URL, manifest: AppHealthExportManifest) throws {}
    func close() {}

    func count(type: String) -> Int { records.filter { $0.type == type }.count }

    func events() -> [AppHealthEventRecord] {
        records.compactMap { record -> AppHealthEventRecord? in
            if case .event(let event) = record.body { return event }
            return nil
        }
    }

    func samples(app: String? = nil, why: AppHealthWriteReason) -> Int {
        records.filter {
            guard case .sample(let sample) = $0.body else { return false }
            return sample.why == why && (app == nil || sample.app == app)
        }.count
    }
}

private actor FakeAppHealthSampler: AppHealthSampling {
    private let usage: [String: AppHealthAppUsage]
    private(set) var sampleCount = 0
    private(set) var resetCount = 0

    init(usage: [String: AppHealthAppUsage]) { self.usage = usage }

    func resetBaselines() { resetCount += 1 }

    func sample(_ apps: [AppHealthWatchedApp]) -> AppHealthSamplerResult {
        sampleCount += 1
        return AppHealthSamplerResult(interval: 20, usage: usage, costMilliseconds: 1)
    }
}

private final class FakeAppHealthObservers: AppHealthSystemObserving {
    private var handler: ((AppHealthSystemEvent) -> Void)?
    var isStarted: Bool { handler != nil }

    func start(_ handler: @escaping (AppHealthSystemEvent) -> Void) { self.handler = handler }
    func stop() { handler = nil }
    func send(_ event: AppHealthSystemEvent) { handler?(event) }
}

nonisolated private struct FakeAppHealthHangChecker: AppHealthHangChecking {
    func check(pid: pid_t) async -> AppHealthHangCheck { AppHealthHangCheck(result: .ok, milliseconds: 1) }
}

nonisolated private struct FakeAppHealthCrashReports: AppHealthCrashReportLooking {
    func hasReport(executableName: String, since: Date) async -> Bool { true }
}

/// Polls until `condition` holds. The deadline is generous because the whole suite runs in parallel and long
/// main-actor suites (Core ML training, synthetic playback) can hold these tests up for several seconds; an
/// uncontended run still returns within a few milliseconds.
@MainActor
private func appHealthEventually(timeout: Duration = .seconds(30), _ condition: () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return await condition()
}
