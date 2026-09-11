// ddock-bench: the external half of the DDock benchmark suite. `benchmarks/run.sh` builds and drives it.
//
//   ddock-bench sample --seconds 600 --out idle.json --process ddock=<pid> --process dock=<pid>
//   ddock-bench e2e --geometry geometry.json --iterations 100
//   ddock-bench report --run <dir> --commit <sha> --budgets budgets.json --out <benchmarks dir> [--strict]
import Foundation

var arguments = Array(CommandLine.arguments.dropFirst())

func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

func options(_ name: String) -> [String] {
    arguments.indices.filter { arguments[$0] == name && $0 + 1 < arguments.count }.map { arguments[$0 + 1] }
}

func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data("ddock-bench: \(message)\n".utf8))
    exit(code)
}

switch arguments.first {
case "sample":
    guard let seconds = option("--seconds").flatMap(Double.init), let out = option("--out") else {
        fail("sample needs --seconds and --out")
    }
    let processes = options("--process").compactMap { pair -> (String, pid_t)? in
        let parts = pair.split(separator: "=")
        guard parts.count == 2, let pid = pid_t(parts[1]) else { return nil }
        return (String(parts[0]), pid)
    }
    guard !processes.isEmpty else { fail("sample needs at least one --process name=pid") }
    let report = Sampler.run(processes: processes, seconds: seconds)
    try Output.write(report, to: URL(fileURLWithPath: out))
case "e2e":
    guard let geometry = option("--geometry") else { fail("e2e needs --geometry") }
    let iterations = option("--iterations").flatMap(Int.init) ?? 100
    EndToEnd.run(geometry: URL(fileURLWithPath: geometry), iterations: iterations)
case "report":
    guard let run = option("--run"), let out = option("--out") else { fail("report needs --run and --out") }
    let passed = try Report.run(stages: URL(fileURLWithPath: run), output: URL(fileURLWithPath: out),
                                commit: option("--commit") ?? "unknown",
                                budgets: option("--budgets").map(URL.init(fileURLWithPath:)))
    if !passed && arguments.contains("--strict") { exit(1) }
default:
    fail("usage: ddock-bench sample|e2e|report …")
}

enum Output {
    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
