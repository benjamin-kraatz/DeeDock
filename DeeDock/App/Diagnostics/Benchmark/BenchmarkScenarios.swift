import AppKit

/// Scripted interactions that drive the real coordinators in-process at a fixed pace.
///
/// These avoid native input, so they need no Accessibility grant and repeat closely between runs, but
/// they skip event delivery. `benchmarks/` covers that path with the `e2e` stage. The pointer must stay
/// still during a run: the dock holds itself visible and ignores real pointer movement until the end.
@MainActor
struct BenchmarkScenarios {
    let coordinator: DockCoordinator
    let recorder: BenchmarkRecorder
    let iterations: Int
    /// Scenario names to run; `nil` runs all of them.
    let only: Set<String>?
    private let warmUp = 5
    /// Fixed, typo-including queries that exercise prefix, fuzzy, and no-result ranking.
    private static let queries = ["sa", "saf", "safari", "term", "notes", "xcod", "mail", "music", "zzqx",
                                  "cal", "pho", "syst", "sett", "find", "activ", "mess", "maps", "prev",
                                  "txet", "key"]

    /// The first dock with laid-out application icons, waiting up to ten seconds for displays to settle.
    static func readyPanel(_ coordinator: DockCoordinator) async -> DockPanelController? {
        for _ in 0..<100 {
            if let panel = coordinator.benchmarkPanels.first(where: { !$0.benchmarkSweep(steps: 2).isEmpty }) {
                return panel
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    func run() async -> BenchmarkStageReport {
        guard let panel = await Self.readyPanel(coordinator) else {
            var report = recorder.report(stage: "scenarios")
            report.skipped["all"] = "No dock with application icons appeared within 10 seconds."
            return report
        }
        panel.benchmarkHold = true
        // Let the first layout, icon decoding, and any launch-time discovery settle.
        await pause(2_000)
        var skipped: [String: String] = [:]
        func runs(_ name: String) -> Bool { only?.contains(name) ?? true }
        if runs("magnify") { await magnify(panel) }
        if runs("stacks"), let reason = await stacks(panel) { skipped["stackOpen"] = reason }
        if runs("peek"), let reason = await peeks(panel) { skipped["peekOpen"] = reason }
        if runs("launcher") { await launcher(panel) }
        if runs("queries") { await launcherQueries(panel) }
        if runs("windowSearch") { await windowSearch() }
        panel.benchmarkHold = false
        var report = recorder.report(stage: "scenarios")
        report.skipped.merge(skipped) { current, _ in current }
        report.context["iterations"] = "\(iterations)"
        return report
    }

    /// Sweeps the pointer across the icons, one step per frame, alternating direction.
    private func magnify(_ panel: DockPanelController) async {
        let points = panel.benchmarkSweep(steps: 120)
        let passes = max(2, Int((Double(iterations * 3) / Double(points.count)).rounded(.up)))
        recorder.paused = true
        await sweep(points, panel: panel)
        recorder.paused = false
        await recorder.measureFrames("magnify", on: panel.benchmarkView) {
            for pass in 0..<passes { await sweep(pass.isMultiple(of: 2) ? points.reversed() : points, panel: panel) }
        }
        panel.interaction.setPointer(nil)
        await pause(500)
    }

    private func sweep(_ points: [CGPoint], panel: DockPanelController) async {
        for point in points {
            let interval = PerformanceSignposts.begin(.magnifyUpdate)
            panel.interaction.setPointer(point)
            PerformanceSignposts.endAfterCommit(interval)
            await pause(16)
        }
    }

    private func stacks(_ panel: DockPanelController) async -> String? {
        let folders = Array(panel.store.folders.filter(\.isAvailable).prefix(3))
        guard !folders.isEmpty else { return "No available folder is pinned to the dock." }
        await repeatMeasured { index in
            coordinator.benchmarkShowStack(folders[index % folders.count], on: panel)
            await pause(350)
            coordinator.benchmarkCloseStack()
            await pause(250)
        }
        return nil
    }

    private func peeks(_ panel: DockPanelController) async -> String? {
        let running = Array(panel.store.items.filter { $0.isRunning && $0.isAvailable }.prefix(3))
        guard !running.isEmpty else { return "No running application is in the dock." }
        let before = recorder.samples[.peekOpen]?.count ?? 0
        coordinator.benchmarkShowPeek(running[0], on: panel)
        await pause(400)
        coordinator.benchmarkClosePeek()
        guard (recorder.samples[.peekOpen]?.count ?? 0) > before else {
            return "Window Peek did not open. It may be disabled, or Accessibility access is missing."
        }
        await repeatMeasured { index in
            coordinator.benchmarkShowPeek(running[index % running.count], on: panel)
            await pause(400)
            coordinator.benchmarkClosePeek()
            await pause(250)
        }
        return nil
    }

    private func launcher(_ panel: DockPanelController) async {
        await recorder.measureFrames("launcher", on: panel.benchmarkView) {
            await repeatMeasured { _ in
                panel.openLauncher()
                await pause(700)
                panel.closeLauncher()
                await pause(300)
            }
        }
    }

    /// Types each query into an open launcher. Results include the search's 120 ms debounce.
    private func launcherQueries(_ panel: DockPanelController) async {
        panel.openLauncher()
        await pause(800)
        var typed = 0
        recorder.paused = true
        while typed < iterations + warmUp {
            for query in Self.queries where typed < iterations + warmUp {
                recorder.paused = typed < warmUp
                panel.launcher.query = query
                await pause(450)
                typed += 1
            }
            recorder.paused = true
            panel.launcher.query = ""
            await pause(200)
        }
        recorder.paused = false
        panel.closeLauncher()
        await pause(300)
    }

    /// Fewer iterations: each opens a real titled window and discovers every window on the system.
    private func windowSearch() async {
        await repeatMeasured(count: max(10, iterations / 4)) { _ in
            coordinator.searchWindows()
            await pause(600)
            coordinator.benchmarkCloseWindowSearch()
            await pause(300)
        }
    }

    /// Runs `warmUp` paused iterations, then `count` recorded ones.
    private func repeatMeasured(count: Int? = nil, _ body: (Int) async -> Void) async {
        let count = count ?? iterations
        for index in 0..<(warmUp + count) {
            recorder.paused = index < warmUp
            await body(index)
        }
        recorder.paused = false
    }

    private func pause(_ milliseconds: Int) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }
}
