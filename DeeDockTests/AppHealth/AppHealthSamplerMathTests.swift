import Foundation
import Testing
@testable import DeeDock

/// The sampler's pure parts: mach time conversion, per-process deltas, per-app aggregation, and attribution.
struct AppHealthSamplerMathTests {
    private func counters(_ cpu: Double, _ wakeups: UInt64, _ energy: UInt64) -> AppHealthProcessCounters {
        AppHealthProcessCounters(cpuSeconds: cpu, idleWakeups: wakeups, energy: energy)
    }

    @Test("Apple Silicon's 125/3 timebase turns mach units into seconds")
    func timebase() {
        let appleSilicon = AppHealthMachTimebase(numerator: 125, denominator: 3)
        #expect(abs(appleSilicon.seconds(24_000_000) - 1.0) < 1e-9)
        #expect(AppHealthMachTimebase(numerator: 1, denominator: 1).seconds(2_500_000_000) == 2.5)
    }

    @Test("A process seen last tick contributes the difference")
    func knownProcess() {
        let delta = AppHealthDeltaMath.delta(current: counters(12.5, 300, 9_000), previous: counters(10, 100, 4_000),
                                             startedAt: 10, previousTickAt: 1_000)
        #expect(delta == counters(2.5, 200, 5_000))
    }

    @Test("A counter that moved backwards contributes zero, never a wrapped value")
    func backwardsCounter() {
        let delta = AppHealthDeltaMath.delta(current: counters(5, 50, 100), previous: counters(10, 100, 4_000),
                                             startedAt: 10, previousTickAt: 1_000)
        #expect(delta == .zero)
    }

    @Test("A new process that started after the previous tick contributes everything")
    func newProcess() {
        let current = counters(1.5, 40, 800)
        #expect(AppHealthDeltaMath.delta(current: current, previous: nil, startedAt: 1_001, previousTickAt: 1_000)
                == current)
    }

    @Test("A process first seen now that started earlier is only a baseline")
    func newlySeenOldProcess() {
        #expect(AppHealthDeltaMath.delta(current: counters(100, 9_000, 1), previous: nil, startedAt: 999,
                                         previousTickAt: 1_000) == .zero)
        // A baseline pass has no previous tick: nothing counts.
        #expect(AppHealthDeltaMath.delta(current: counters(100, 9_000, 1), previous: nil, startedAt: 5_000,
                                         previousTickAt: nil) == .zero)
    }

    @Test("Usage splits main and helper CPU, sums memory, and keeps energy unavailable without a reporter")
    func aggregation() {
        var usage = AppHealthAppUsage()
        usage.add(counters(2, 10, 0), footprint: 300, reportsEnergy: false, isMain: true)
        usage.add(counters(5, 30, 0), footprint: 200, reportsEnergy: false, isMain: false)
        #expect(usage.cpuMain == 2)
        #expect(usage.cpuHelpers == 5)
        #expect(usage.mem == 500)
        #expect(usage.memMain == 300)
        #expect(usage.procs == 2)
        #expect(usage.wakeups == 40)
        #expect(usage.energy == nil)
        usage.add(counters(0, 0, 0), footprint: 0, reportsEnergy: true, isMain: false)
        #expect(usage.energy == 0)
    }

    @Test("Load names which processes carried the CPU")
    func load() {
        #expect(AppHealthLoad(cpuMain: 0, cpuHelpers: 0) == AppHealthLoad.none)
        #expect(AppHealthLoad(cpuMain: 1, cpuHelpers: 1) == .main)
        #expect(AppHealthLoad(cpuMain: 1, cpuHelpers: 1.5) == .helpers)
    }

    @Test("The parent chain attributes main processes and their descendants")
    func parentChain() {
        let parents: [pid_t: pid_t] = [100: 1, 101: 100, 102: 101, 200: 1, 300: 250]
        let mains: [pid_t: String] = [100: "com.example.Editor"]
        #expect(AppHealthAttribution.owner(of: 100, parents: parents, mainProcesses: mains)
                == .init(app: "com.example.Editor", role: .main))
        #expect(AppHealthAttribution.owner(of: 102, parents: parents, mainProcesses: mains)
                == .init(app: "com.example.Editor", role: .helper))
        // Reaches launchd, or a parent missing from the table: left to path attribution.
        #expect(AppHealthAttribution.owner(of: 200, parents: parents, mainProcesses: mains) == nil)
        #expect(AppHealthAttribution.owner(of: 300, parents: parents, mainProcesses: mains) == nil)
    }

    @Test("A parent cycle ends the walk instead of looping")
    func parentCycle() {
        let parents: [pid_t: pid_t] = [10: 11, 11: 10]
        #expect(AppHealthAttribution.owner(of: 10, parents: parents, mainProcesses: [:]) == nil)
    }

    @Test("Path attribution matches inside a bundle, longest bundle first, never a sibling prefix")
    func pathAttribution() {
        let bundles = [(path: "/Applications/Xcode.app", app: "com.apple.dt.Xcode"),
                       (path: "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app",
                        app: "com.apple.iphonesimulator")]
        #expect(AppHealthAttribution.owner(
            executablePath: "/Applications/Xcode.app/Contents/SharedFrameworks/X.xpc/Contents/MacOS/X",
            bundles: bundles) == "com.apple.dt.Xcode")
        #expect(AppHealthAttribution.owner(
            executablePath: "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app/Contents/MacOS/H",
            bundles: bundles) == "com.apple.iphonesimulator")
        #expect(AppHealthAttribution.owner(executablePath: "/Applications/Xcode.app.bak/Contents/MacOS/X",
                                           bundles: bundles) == nil)
    }
}
