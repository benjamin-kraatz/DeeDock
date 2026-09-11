import AppKit
import Foundation
import IOKit.ps

/// One published number with how it was obtained.
struct MetricSummary: Codable {
    var distribution: BenchmarkDistribution
    var stage: String
    /// Repeated runs merged into this row. For launch, the number of launches.
    var runs: Int
    /// Lowest and highest p50 across runs, when there was more than one run.
    var p50Range: [Double]?
}

struct BudgetResult: Codable {
    var key: String
    var label: String
    var limit: Double
    var value: Double?
    var passed: Bool?
}

/// The merged, publishable result of one `run.sh` invocation. `results/latest.json` is this type.
struct RunSummary: Codable {
    var schema = 1
    var date: String
    var commit: String
    var machine: [String: String]
    var metrics: [String: MetricSummary] = [:]
    var frames: [String: BenchmarkFrameSummary] = [:]
    /// `ddock` and `dock` come from the idle stage; `ddockScenarios` is DDock while scenarios ran.
    var resources: [String: ProcessResourceSummary] = [:]
    var context: [String: String] = [:]
    var skipped: [String: String] = [:]
    var budgets: [BudgetResult] = []
}

private struct Budget: Codable {
    var key: String
    var stat: String?
    var max: Double
    var label: String
}

enum Report {
    /// Returns whether every budget with a measured value passed.
    static func run(stages directory: URL, output: URL, commit: String, budgets: URL?) throws -> Bool {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "geometry.json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let reports = try files.map { try JSONDecoder().decode(BenchmarkStageReport.self, from: Data(contentsOf: $0)) }
        guard !reports.isEmpty else { fail("No stage results in \(directory.path).") }

        let date = ISO8601DateFormatter().string(from: Date())
        var summary = RunSummary(date: date, commit: commit, machine: machine())
        merge(reports, into: &summary)
        if let budgets {
            let list = try JSONDecoder().decode([Budget].self, from: Data(contentsOf: budgets))
            summary.budgets = list.map { evaluate($0, in: summary) }
        }

        let results = output.appendingPathComponent("results")
        let stamp = date.replacingOccurrences(of: ":", with: "-")
        try Output.write(summary, to: results.appendingPathComponent("\(stamp)-\(commit).json"))
        try Output.write(summary, to: results.appendingPathComponent("latest.json"))
        try Chart.svg(summary).write(to: results.appendingPathComponent("latest.svg"), atomically: true, encoding: .utf8)
        try Markdown.results(summary).write(to: output.appendingPathComponent("RESULTS.md"), atomically: true, encoding: .utf8)

        for budget in summary.budgets {
            let mark = budget.passed.map { $0 ? "pass" : "FAIL" } ?? "n/a "
            let value = budget.value.map { Format.number($0) } ?? "–"
            print("[\(mark)] \(budget.label): \(value) (limit \(Format.number(budget.limit)))")
        }
        print("Wrote \(output.appendingPathComponent("RESULTS.md").path)")
        return summary.budgets.allSatisfy { $0.passed != false }
    }

    private static func merge(_ reports: [BenchmarkStageReport], into summary: inout RunSummary) {
        // Launch runs one sample per process start, so launches pool into a single distribution.
        let launches = reports.filter { $0.stage == "launch" }.compactMap { $0.metrics["launch"]?.p50 }
        if let distribution = BenchmarkDistribution(samples: launches) {
            summary.metrics["launch"] = MetricSummary(distribution: distribution, stage: "launch", runs: launches.count)
        }
        // Other stages: each run already holds hundreds of samples. Publish the run with the median p50
        // and show the spread, rather than averaging percentiles, which is statistically meaningless.
        for stage in ["scenarios", "e2e", "micro"] {
            let runs = reports.filter { $0.stage == stage }
            // Every stage records its own launch as a side effect; only the launch stage's pooled row counts.
            for name in Set(runs.flatMap(\.metrics.keys)) where name != "launch" {
                let candidates = runs.compactMap { $0.metrics[name] }.sorted { $0.p50 < $1.p50 }
                guard !candidates.isEmpty else { continue }
                summary.metrics[name] = MetricSummary(
                    distribution: candidates[(candidates.count - 1) / 2], stage: stage, runs: candidates.count,
                    p50Range: candidates.count > 1 ? [candidates.first!.p50, candidates.last!.p50] : nil)
            }
            for scenario in Set(runs.flatMap(\.frames.keys)) {
                let candidates = runs.compactMap { $0.frames[scenario] }.sorted { $0.hitchRatio < $1.hitchRatio }
                summary.frames[scenario] = candidates[(candidates.count - 1) / 2]
            }
        }
        for report in reports {
            if report.stage == "idle" { summary.resources.merge(report.resources) { current, _ in current } }
            if report.stage == "scenarios", let ddock = report.resources["ddock"], summary.resources["ddockScenarios"] == nil {
                summary.resources["ddockScenarios"] = ddock
            }
            summary.context.merge(report.context) { current, _ in current }
            for (key, reason) in report.skipped { summary.skipped["\(report.stage).\(key)"] = reason }
        }
        // Reveal latency includes the user's reveal delay by design. Publish the part DDock controls too.
        if let reveal = summary.metrics["dockReveal"], let delay = summary.context["revealDelay"].flatMap(Double.init) {
            var shifted = reveal
            let offset = delay * 1_000
            shifted.distribution = BenchmarkDistribution(shifting: reveal.distribution, by: -offset)
            shifted.p50Range = reveal.p50Range?.map { $0 - offset }
            summary.metrics["dockRevealOverDelay"] = shifted
        }
    }

    private static func evaluate(_ budget: Budget, in summary: RunSummary) -> BudgetResult {
        let parts = budget.key.split(separator: ".").map(String.init)
        var value: Double?
        switch parts.first {
        case "resources" where parts.count == 3:
            let usage = summary.resources[parts[1]]
            switch parts[2] {
            case "cpuPercent": value = usage?.cpuPercent
            case "wakeupsPerSecond": value = usage?.wakeupsPerSecond
            case "footprintMiB": value = usage?.footprintMiB?.p50
            default: break
            }
        case "frames" where parts.count == 3 && parts[2] == "hitchRatio":
            value = summary.frames[parts[1]]?.hitchRatio
        default:
            if let distribution = summary.metrics[budget.key]?.distribution {
                switch budget.stat ?? "p95" {
                case "p50": value = distribution.p50
                case "p90": value = distribution.p90
                case "p99": value = distribution.p99
                case "max": value = distribution.max
                default: value = distribution.p95
                }
            }
        }
        return BudgetResult(key: budget.key + (budget.stat.map { ".\($0)" } ?? ""), label: budget.label,
                            limit: budget.max, value: value, passed: value.map { $0 <= budget.max })
    }

    /// Hardware and conditions that a reader needs to judge the numbers.
    private static func machine() -> [String: String] {
        func sysctl(_ name: String) -> String? {
            var size = 0
            guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
            var buffer = [CChar](repeating: 0, count: size)
            guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
            return String(cString: buffer)
        }
        var memory: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &memory, &size, nil, 0)
        let displays = NSScreen.screens.map { screen in
            let size = screen.frame.size
            return "\(Int(size.width))×\(Int(size.height))@\(Int(screen.backingScaleFactor))x"
                + " \(screen.maximumFramesPerSecond) Hz"
        }
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let power = IOPSGetProvidingPowerSourceType(info).takeUnretainedValue() as String
        return [
            "model": sysctl("hw.model") ?? "unknown",
            "chip": sysctl("machdep.cpu.brand_string") ?? "unknown",
            "memory": "\(memory / 1_073_741_824) GB",
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "displays": displays.joined(separator: ", "),
            "power": power == kIOPMACPowerKey ? "AC" : power,
            "lowPowerMode": "\(ProcessInfo.processInfo.isLowPowerModeEnabled)",
            "thermalState": "\(ProcessInfo.processInfo.thermalState.rawValue)",
        ]
    }
}

extension BenchmarkDistribution {
    /// Every statistic moved by a constant, used to subtract a configured delay.
    init(shifting base: BenchmarkDistribution, by offset: Double) {
        self = base
        min += offset; p50 += offset; p90 += offset; p95 += offset; p99 += offset; max += offset; mean += offset
    }
}

enum Format {
    static func number(_ value: Double) -> String {
        switch abs(value) {
        case 100...: String(format: "%.0f", value)
        case 10...: String(format: "%.1f", value)
        default: String(format: "%.2f", value)
        }
    }
}
