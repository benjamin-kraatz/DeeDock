import Foundation
import Testing
@testable import DeeDock

/// Labelling on top of a controller with faked services: what a prompt writes, how it ends, and how pauses and
/// switches interrupt it. No panels, no libproc, no files.
@MainActor
struct AppHealthLabellingCoordinatorTests {
    private let busy = AppHealthWatchedApp(bundleID: "com.example.Busy", kind: .regular, pid: 100, bundlePath: nil)

    private final class Clock {
        var date = Date(timeIntervalSince1970: 1_793_000_000)
    }

    private struct Harness {
        let controller: AppHealthController
        let coordinator: AppHealthLabellingCoordinator
        let store: LabellingFakeStore
        let prompts: LabellingFakePrompts
        let pickers: LabellingFakePickers
        let clock: Clock
    }

    /// - Parameters:
    ///   - fastTimers: Question timers run 1000× faster; otherwise they never fire during a test.
    ///   - ticking: Ticks every 5 ms (writing `lastTick`); otherwise only the baseline pass runs.
    private func makeHarness(fastTimers: Bool = false, ticking: Bool = false) -> Harness {
        let store = LabellingFakeStore()
        let clock = Clock()
        let apps = [busy]
        let dependencies = AppHealthControllerDependencies(
            sampler: LabellingFakeSampler(usage: [busy.bundleID: AppHealthAppUsage(mem: 400_000_000,
                                                                                    memMain: 400_000_000, procs: 1)]),
            store: store, hangChecker: LabellingFakeHangChecker(), crashReports: LabellingFakeCrashReports(),
            observers: LabellingFakeObservers(),
            snapshot: { date, power, thermal in
                AppHealthSystemSnapshot(date: date, apps: apps, frontmost: nil, idleSeconds: 0, power: power,
                                        thermal: thermal, accessibilityTrusted: false)
            },
            powerSource: { .ac }, thermalState: { .nominal },
            waitForNextTick: { try await Task.sleep(for: ticking ? .milliseconds(5) : .seconds(3600)) },
            crashReportDelay: { try await Task.sleep(for: .seconds(3600)) },
            now: { Date() }, appVersion: { "test" })
        let controller = AppHealthController(
            settings: AppHealthSettingsStore(defaults: nil, initial: .init(collecting: true, labelling: true)),
            labelling: AppHealthLabellingPreferences(defaults: nil), dependencies: dependencies)
        controller.anchorProvider = { _ in AppHealthAnchor.screen(visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875)) }
        let prompts = LabellingFakePrompts()
        let pickers = LabellingFakePickers()
        let coordinator = AppHealthLabellingCoordinator(controller: controller, dependencies: AppHealthLabellingDependencies(
            now: { clock.date },
            sleep: { duration in try await Task.sleep(for: fastTimers ? duration / 1000 : .seconds(3600)) },
            random: { 0 },
            ownBundleID: "dev.dokk.app",
            appDisplays: { ids in
                Dictionary(uniqueKeysWithValues: ids.map { ($0, AppHealthAppDisplay(bundleID: $0, name: $0, icon: nil)) })
            },
            announce: { _ in },
            presentPrompt: { session, _, _ in prompts.present(session) },
            presentPicker: { entries in pickers.present(entries) }))
        return Harness(controller: controller, coordinator: coordinator, store: store, prompts: prompts,
                       pickers: pickers, clock: clock)
    }

    private func start(_ harness: Harness) {
        harness.coordinator.start()
        harness.controller.start()
    }

    private func stop(_ harness: Harness) {
        harness.controller.stop()
        harness.coordinator.stop()
    }

    private let spin = AppHealthPromptCandidate(app: "com.example.Busy", kind: .regular, trigger: .rule,
                                                reasons: [.cpu, .background],
                                                evidence: AppHealthSuspicionEvidence(meanCPUPercent: 140,
                                                                                     shortWindowSeconds: 180))

    @Test("A prompt writes its record and records itself for the caps; expiry writes noAnswer and closes it")
    func expiry() async throws {
        let harness = makeHarness(fastTimers: true)
        start(harness)
        harness.coordinator.showPrompt(spin)
        #expect(harness.coordinator.isPromptVisible)
        #expect(harness.controller.labelling.promptHistory.triggers == [.rule])

        #expect(await labellingEventually { harness.prompts.closed == 1 })
        #expect(!harness.coordinator.isPromptVisible)
        #expect(await labellingEventually { await harness.store.labels().count == 1 })
        let prompt = try #require(await harness.store.prompts().first)
        let label = try #require(await harness.store.labels().first)
        #expect(prompt.trigger == .rule)
        #expect(prompt.reasons == [.cpu, .background])
        #expect(prompt.anchor == .screen)
        #expect(label.id == prompt.id)
        #expect(label.answer == .noAnswer)
        #expect(!label.dismissed)
        #expect(!label.interrupted)
        #expect(label.source == .prompt)
        stop(harness)
    }

    @Test("An answer labels the five minutes before the prompt appeared")
    func answerWindow() async throws {
        let harness = makeHarness()
        start(harness)
        harness.coordinator.showPrompt(spin)
        let session = try #require(harness.prompts.sessions.last)
        harness.clock.date += 7
        session.answer(.expected)
        #expect(await labellingEventually { await harness.store.labels().count == 1 })
        let label = try #require(await harness.store.labels().first)
        #expect(label.answer == .expected)
        #expect(label.to == 1_793_000_000)
        #expect(label.from == 1_793_000_000 - 300)
        #expect(label.responseSeconds == 7)
        stop(harness)
    }

    @Test("Turning collection off closes an open prompt as interrupted before collectorStop")
    func collectionOffInterrupts() async throws {
        let harness = makeHarness()
        start(harness)
        harness.coordinator.showPrompt(spin)
        harness.controller.setCollecting(false)
        #expect(harness.prompts.closed == 1)
        #expect(!harness.coordinator.isPromptVisible)
        #expect(await labellingEventually { await harness.store.events().last?.event == .collectorStop })
        let label = try #require(await harness.store.labels().first)
        #expect(label.answer == .noAnswer)
        #expect(label.interrupted)
        let types = await harness.store.records.map(\.type).filter { $0 == "label" || $0 == "event" }
        #expect(types.suffix(2) == ["label", "event"])
        stop(harness)
    }

    @Test("Turning labelling off closes an open prompt as interrupted and stops listening to ticks")
    func labellingOffInterrupts() async throws {
        let harness = makeHarness()
        start(harness)
        #expect(harness.controller.tickCompleted != nil)
        harness.coordinator.showPrompt(spin)
        harness.controller.setLabelling(false)
        #expect(await labellingEventually { harness.prompts.closed == 1 })
        #expect(harness.controller.tickCompleted == nil)
        #expect(await labellingEventually { await harness.store.labels().first?.interrupted == true })
        stop(harness)
    }

    @Test("Don't ask about this app dismisses the prompt and adds the app to the list")
    func dontAsk() async throws {
        let harness = makeHarness()
        start(harness)
        harness.coordinator.showPrompt(spin)
        try #require(harness.prompts.sessions.last).perform(.dontAsk)
        #expect(harness.prompts.closed == 1)
        #expect(harness.controller.labelling.dontAsk == ["com.example.Busy"])
        #expect(await labellingEventually { await harness.store.events().contains { $0.event == .dontAsk } })
        #expect(await harness.store.labels().first?.dismissed == true)
        stop(harness)
    }

    @Test("Manual: closing the list writes nothing; a picked app writes a manual prompt and label")
    func manualLabel() async throws {
        let harness = makeHarness(ticking: true)
        start(harness)
        #expect(await labellingEventually { harness.controller.lastTick != nil })

        harness.coordinator.showPicker()
        let first = try #require(harness.pickers.pickers.last)
        #expect(first.entries.map(\.id) == ["com.example.Busy"])
        first.dismissed?()
        #expect(first.closed)

        harness.coordinator.showPicker()
        let picker = try #require(harness.pickers.pickers.last)
        let pickedAt = harness.clock.date
        picker.picked?(try #require(picker.entries.first))
        let session = try #require(picker.question)
        session.answer(.notSure)
        #expect(await labellingEventually { await harness.store.labels().count == 1 })
        let prompt = try #require(await harness.store.prompts().first)
        let label = try #require(await harness.store.labels().first)
        #expect(await harness.store.prompts().count == 1)
        #expect(prompt.trigger == .manual)
        #expect(prompt.reasons.isEmpty)
        #expect(label.source == .manual)
        #expect(label.answer == .notSure)
        #expect(label.to == pickedAt.timeIntervalSince1970)
        // Manual labels leave the caps alone.
        #expect(harness.controller.labelling.promptHistory == AppHealthPromptHistory())
        stop(harness)
    }

    @Test("Sleep closes a picked app's question as interrupted, and the picker")
    func manualInterrupted() async throws {
        let harness = makeHarness(ticking: true)
        start(harness)
        #expect(await labellingEventually { harness.controller.lastTick != nil })
        harness.coordinator.showPicker()
        let picker = try #require(harness.pickers.pickers.last)
        picker.picked?(try #require(picker.entries.first))
        harness.controller.setCollecting(false)
        #expect(picker.closed)
        #expect(await labellingEventually { await harness.store.labels().first?.interrupted == true })
        stop(harness)
    }
}

// MARK: - Fakes

@MainActor
private final class LabellingFakePrompt: AppHealthPromptPresenting {
    let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func close() { onClose() }
}

@MainActor
private final class LabellingFakePrompts {
    private(set) var sessions: [AppHealthLabelSession] = []
    private(set) var closed = 0

    func present(_ session: AppHealthLabelSession) -> any AppHealthPromptPresenting {
        sessions.append(session)
        return LabellingFakePrompt { [weak self] in self?.closed += 1 }
    }
}

@MainActor
private final class LabellingFakePicker: AppHealthPickerPresenting {
    let entries: [AppHealthPickerEntry]
    var picked: ((AppHealthPickerEntry) -> Void)?
    var dismissed: (() -> Void)?
    private(set) var question: AppHealthLabelSession?
    private(set) var closed = false

    init(entries: [AppHealthPickerEntry]) { self.entries = entries }
    func showQuestion(_ session: AppHealthLabelSession) { question = session }
    func present() {}
    func close() { closed = true }
}

@MainActor
private final class LabellingFakePickers {
    private(set) var pickers: [LabellingFakePicker] = []

    func present(_ entries: [AppHealthPickerEntry]) -> any AppHealthPickerPresenting {
        let picker = LabellingFakePicker(entries: entries)
        pickers.append(picker)
        return picker
    }
}

private actor LabellingFakeStore: AppHealthRecording {
    private(set) var records: [AppHealthRecord] = []

    func append(_ records: [AppHealthRecord]) { self.records += records }
    func summary() -> AppHealthStorageSummary { .empty }
    func deleteAll() throws { records.removeAll() }
    func export(to destination: URL, manifest: AppHealthExportManifest) throws {}
    func close() {}

    func events() -> [AppHealthEventRecord] {
        records.compactMap { record -> AppHealthEventRecord? in
            if case .event(let event) = record.body { return event }
            return nil
        }
    }

    func prompts() -> [AppHealthPromptRecord] {
        records.compactMap { record -> AppHealthPromptRecord? in
            if case .prompt(let prompt) = record.body { return prompt }
            return nil
        }
    }

    func labels() -> [AppHealthLabelRecord] {
        records.compactMap { record -> AppHealthLabelRecord? in
            if case .label(let label) = record.body { return label }
            return nil
        }
    }
}

private actor LabellingFakeSampler: AppHealthSampling {
    private let usage: [String: AppHealthAppUsage]
    init(usage: [String: AppHealthAppUsage]) { self.usage = usage }
    func resetBaselines() {}
    func sample(_ apps: [AppHealthWatchedApp]) -> AppHealthSamplerResult {
        AppHealthSamplerResult(interval: 20, usage: usage, costMilliseconds: 1)
    }
}

@MainActor
private final class LabellingFakeObservers: AppHealthSystemObserving {
    func start(_ handler: @escaping (AppHealthSystemEvent) -> Void) {}
    func stop() {}
}

nonisolated private struct LabellingFakeHangChecker: AppHealthHangChecking {
    func check(pid: pid_t) async -> AppHealthHangCheck { AppHealthHangCheck(result: .ok, milliseconds: 1) }
}

nonisolated private struct LabellingFakeCrashReports: AppHealthCrashReportLooking {
    func hasReport(executableName: String, since: Date) async -> Bool { false }
}
