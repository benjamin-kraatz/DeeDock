import AppKit

/// Runs a benchmark stage when DDock is launched with `-DDockBenchmark <stage>`. A normal launch creates none.
///
/// Arguments (read from the launch-argument defaults domain, never persisted):
/// - `-DDockBenchmark launch|scenarios|e2e`
/// - `-DDockBenchmarkOutput <path>`: stage JSON. Required.
/// - `-DDockBenchmarkIterations <n>`: measured iterations per scenario (default 200).
/// - `-DDockBenchmarkScenarios <a,b>`: `scenarios` only; a subset of magnify, stacks, peek, launcher,
///   queries, windowSearch.
/// - `-DDockBenchmarkGeometry <path>`: `e2e` only; dock positions for the input runner.
///
/// Benchmarks run against the user's real dock configuration and never change settings. The run
/// ends by terminating the app so the external runner can relaunch a normal instance.
@MainActor
final class BenchmarkRunner {
    static let finishNotification = Notification.Name("de.benjaminkraatz.DeeDock.benchmark.finish")
    static let readyNotification = Notification.Name("de.benjaminkraatz.DeeDock.benchmark.ready")

    private let stage: String
    private let output: URL
    private let iterations: Int
    private let geometry: URL?
    private let scenarios: Set<String>?
    private let recorder = BenchmarkRecorder()
    private var task: Task<Void, Never>?
    private var finishObserver: Any?

    /// Starts recording before the docks exist so launch time is captured. Returns `nil` for a normal launch.
    static func fromLaunchArguments() -> BenchmarkRunner? {
        let defaults = UserDefaults.standard
        guard let stage = defaults.string(forKey: "DDockBenchmark"),
              let output = defaults.string(forKey: "DDockBenchmarkOutput") else { return nil }
        let iterations = defaults.integer(forKey: "DDockBenchmarkIterations")
        let runner = BenchmarkRunner(stage: stage, output: URL(fileURLWithPath: output),
                                     iterations: iterations > 0 ? iterations : 200,
                                     geometry: defaults.string(forKey: "DDockBenchmarkGeometry").map(URL.init(fileURLWithPath:)),
                                     scenarios: defaults.string(forKey: "DDockBenchmarkScenarios")
                                         .map { Set($0.split(separator: ",").map(String.init)) })
        runner.recorder.start()
        PerformanceSignposts.tracksInput = stage == "e2e"
        return runner
    }

    private init(stage: String, output: URL, iterations: Int, geometry: URL?, scenarios: Set<String>?) {
        self.stage = stage; self.output = output; self.iterations = iterations
        self.geometry = geometry; self.scenarios = scenarios
    }

    func run(_ coordinator: DockCoordinator) {
        task = Task { [weak self] in
            guard let self else { return }
            var report: BenchmarkStageReport
            switch stage {
            case "launch": report = await launch()
            case "scenarios": report = await BenchmarkScenarios(coordinator: coordinator, recorder: recorder,
                                                               iterations: iterations, only: scenarios).run()
            case "e2e": report = await endToEnd(coordinator)
            default:
                report = BenchmarkStageReport(stage: stage)
                report.skipped[stage] = "Unknown benchmark stage."
            }
            report.context.merge(Self.context(coordinator)) { current, _ in current }
            finish(report)
        }
    }

    private func launch() async -> BenchmarkStageReport {
        // Launch is reported after the first dock commit; wait for it, but never forever.
        for _ in 0..<100 where recorder.samples[.launch] == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        var report = recorder.report(stage: "launch")
        if report.metrics.isEmpty { report.skipped["launch"] = "No dock appeared within 10 seconds." }
        return report
    }

    /// Records input-to-commit latency for native events posted by `benchmarks/`, until told to finish.
    private func endToEnd(_ coordinator: DockCoordinator) async -> BenchmarkStageReport {
        guard let panel = await BenchmarkScenarios.readyPanel(coordinator), let layout = panel.benchmarkGeometry(),
              let geometry else {
            var report = recorder.report(stage: "e2e")
            report.skipped["e2e"] = "No dock with application icons, or no geometry path."
            return report
        }
        do {
            try JSONEncoder.benchmark.encode(layout).write(to: geometry, options: .atomic)
        } catch {
            var report = recorder.report(stage: "e2e")
            report.skipped["e2e"] = "Could not write geometry: \(error.localizedDescription)"
            return report
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false
            finishObserver = DistributedNotificationCenter.default().addObserver(
                forName: Self.finishNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    guard !resumed else { return }
                    resumed = true; continuation.resume()
                }
            }
            DistributedNotificationCenter.default().postNotificationName(Self.readyNotification, object: nil,
                                                                         userInfo: nil, deliverImmediately: true)
        }
        return recorder.report(stage: "e2e")
    }

    private func finish(_ report: BenchmarkStageReport) {
        recorder.stop()
        if let finishObserver { DistributedNotificationCenter.default().removeObserver(finishObserver) }
        do {
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder.benchmark.encode(report).write(to: output, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("DDock benchmark: \(error.localizedDescription)\n".utf8))
        }
        NSApp.terminate(nil)
    }

    /// Configuration that changes what a number means. App names and paths are never recorded.
    private static func context(_ coordinator: DockCoordinator) -> [String: String] {
        let settings = coordinator.settings.value
        let panels = coordinator.benchmarkPanels
        let bundle = Bundle.main.infoDictionary ?? [:]
        return [
            "appVersion": "\(bundle["CFBundleShortVersionString"] ?? "?") (\(bundle["CFBundleVersion"] ?? "?"))",
            "docks": "\(panels.count)",
            "dockIcons": "\(panels.first?.store.items.count ?? 0)",
            "dockFolders": "\(panels.first?.store.folders.count ?? 0)",
            "iconSize": "\(settings.iconSize)",
            "magnification": "\(settings.magnification)",
            "autoHide": "\(settings.behavior.autoHide)",
            "revealDelay": "\(settings.behavior.revealDelay)",
            "hideDelay": "\(settings.behavior.hideDelay)",
            "animationDuration": "\(settings.behavior.animationDuration)",
            "reduceMotion": "\(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)",
        ]
    }
}

extension JSONEncoder {
    static var benchmark: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
