import Foundation

/// How a probe hands its numbers to the `bench` process that started it: one `RESULT <key> <value>` line each on
/// stdout. Each probe runs in a process of its own so memory figures start from a clean process.
enum BenchResults {
    static let prefix = "RESULT "

    /// Reports one number.
    static func report(_ key: String, _ value: Double) {
        print("\(prefix)\(key) \(value)")
        fflush(stdout)
    }

    /// Reports the memory figures under `stage`, in megabytes.
    static func report(memoryAt stage: String) {
        guard let memory = ProcessMemory.sample() else { return }
        report("\(stage).footprintMB", ProcessMemory.megabytes(memory.footprint))
        report("\(stage).peakFootprintMB", ProcessMemory.megabytes(memory.peakFootprint))
        report("\(stage).residentMB", ProcessMemory.megabytes(memory.resident))
        report("\(stage).metalMB", ProcessMemory.megabytes(memory.metalAllocated))
    }

    /// The `RESULT` lines in `output`, by key; the other lines are echoed to stdout.
    static func parse(_ output: String) -> [String: Double] {
        var results: [String: Double] = [:]
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(prefix) {
                let parts = line.dropFirst(prefix.count).split(separator: " ")
                if parts.count == 2, let value = Double(parts[1]) { results[String(parts[0])] = value }
            } else if !line.isEmpty {
                print(line)
            }
        }
        return results
    }
}
