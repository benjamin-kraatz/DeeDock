import Foundation

/// Samples several processes over the same window, so DDock and the system Dock see identical conditions.
enum Sampler {
    static func run(processes: [(name: String, pid: pid_t)], seconds: Double, interval: Double = 1) -> BenchmarkStageReport {
        var series = Dictionary(uniqueKeysWithValues: processes.map { ($0.name, [ProcessResourceSample]()) })
        var report = BenchmarkStageReport(stage: "idle")
        let end = ProcessInfo.processInfo.systemUptime + seconds
        print("Sampling \(processes.map(\.name).joined(separator: ", ")) for \(Int(seconds)) s. Leave the Mac idle.")
        while ProcessInfo.processInfo.systemUptime <= end {
            for (name, pid) in processes {
                if let sample = ProcessResourceSample(pid: pid) { series[name]?.append(sample) }
                else if report.skipped[name] == nil { report.skipped[name] = "Process \(pid) exited or could not be read." }
            }
            Thread.sleep(forTimeInterval: interval)
        }
        for (name, samples) in series {
            report.resources[name] = ProcessResourceSummary(process: name, samples: samples)
        }
        report.context["idleSeconds"] = "\(Int(seconds))"
        return report
    }
}
