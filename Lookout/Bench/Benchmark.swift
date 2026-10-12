import Foundation

/// `LookoutBench bench`: runs each probe in a child process of its own (so one probe's memory doesn't show in the
/// next one's figures), then prints the measurements and the phase 0 decision gate.
///
/// Order matters for the cold start: the text probe goes first, so a run right after a build also shows what the very
/// first start costs, before Metal's shader cache holds this binary's pipelines.
enum Benchmark {
    /// One row of the decision gate.
    struct Gate {
        let name: String
        let measured: String
        let limit: String
        let passed: Bool?
    }

    /// Returns the exit status: 0 when every gate passes.
    ///
    /// - Throws: A probe couldn't be started.
    static func run(models: URL, references: URL?, image: URL?) throws -> Int32 {
        print("LookoutBench: llama.cpp \(LlamaEmbedder.buildTag), vectors \(LlamaEmbedder.vectorVersion), "
              + "\(sysctl("machdep.cpu.brand_string")), \(ProcessInfo.processInfo.physicalMemory >> 30) GB, "
              + "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        var arguments = ["--models", models.path, "--child", "1"]
        if let references { arguments += ["--refs", references.path] }
        let text = try child(["probe-text"] + arguments)
        let full = try child(["probe-full"] + arguments)
        let picture = try child(["probe-image"] + arguments + (image.map { ["--image", $0.path] } ?? []))
        let reference = try references.map { _ in try child(["reference"] + arguments) }
        guard text.status == 0, full.status == 0, picture.status == 0 else {
            throw BenchFailure("a probe failed (text \(text.status), full \(full.status), picture \(picture.status))")
        }
        let r = text.results.merging(full.results) { $1 }.merging(picture.results) { $1 }
            .merging(reference?.results ?? [:]) { $1 }
        printMeasurements(r, hasImages: references != nil)
        let gates = gates(r, hasReferences: references != nil)
        print("\nDecision gate")
        for gate in gates {
            let verdict = gate.passed.map { $0 ? "PASS" : "FAIL" } ?? "n/a "
            print("  \(verdict)  \(pad(gate.name, 30)) \(pad(gate.measured, 34)) limit \(gate.limit)")
        }
        return gates.allSatisfy { $0.passed ?? false } ? 0 : 1
    }

    private static func printMeasurements(_ r: [String: Double], hasImages: Bool) {
        print("\nQuery encoder (text-only, fresh process)")
        row("cold start (load + 2 warm-up embeds)", seconds(r["text.coldStartSeconds"]))
        row("warm query median / p95 (n=\(int(r["text.queryCount"])))",
            "\(ms(r["text.queryMedianMs"])) / \(ms(r["text.queryP95Ms"]))")
        row("warm query min / max", "\(ms(r["text.queryMinMs"])) / \(ms(r["text.queryMaxMs"]))")
        memoryRows(r, "text.loaded", "after load")
        memoryRows(r, "text.queried", "after 30 queries")

        print("\nIndexer configuration (text + mmproj, fresh process)")
        row("load (+ 2 warm-up embeds)", seconds(r["full.loadSeconds"]))
        memoryRows(r, "full.loaded", "after load")
        if hasImages {
            for (file, key) in [("photo.jpg", "photo"), ("screen.png", "screen")] {
                for budget in [280, 140] {
                    let prefix = "full.image.\(key).\(budget)"
                    row("image \(file) @\(budget): median of \(FullProbe.imageRuns) (first)",
                        "\(ms(r["\(prefix).medianMs"])) (\(ms(r["\(prefix).firstMs"])))")
                }
            }
        }
        let count = r["full.batch.count"] ?? 0
        let median = r["full.batch.medianMs"]
        row("batch of \(int(count)) docs (~\(int(r["full.batch.meanCharacters"])) chars): total, median of "
            + "\(FullProbe.batchRuns)", "\(ms(median)) (first \(ms(r["full.batch.firstMs"])))")
        row("batch per item", ms(median.map { $0 / max(count, 1) }))
        memoryRows(r, "full.worked", "after images and batches")

        print("\nPicture search (query service: text model, then the image encoder on the first picture)")
        row("text model start (load + 2 warm-up embeds)", seconds(r["image.textStartSeconds"]))
        row("app: prepare the picture @280 / @140", "\(ms(r["image.prepare280Ms"])) / \(ms(r["image.prepare140Ms"]))")
        row("image encoder load (+ mtmd warm-up)", seconds(r["image.attachSeconds"]))
        row("first picture query @280", ms(r["image.firstQueryMs"]))
        row("cold picture search (load + first query)", seconds(r["image.coldSeconds"]))
        for budget in ["280", "140"] {
            row("warm picture query @\(budget): median / p95 (n=\(ImageProbe.warmRuns)) (first)",
                "\(ms(r["image.warm\(budget).medianMs"])) / \(ms(r["image.warm\(budget).p95Ms"])) "
                    + "(\(ms(r["image.warm\(budget).firstMs"])))")
        }
        row("text query beside the image encoder", ms(r["image.textAfterMs"]))
        memoryRows(r, "image.attached", "after the encoder loaded")
        memoryRows(r, "image.queried", "after picture queries")
    }

    private static func gates(_ r: [String: Double], hasReferences: Bool) -> [Gate] {
        let images = ["photo", "screen"].flatMap { key in [280, 140].compactMap { r["full.image.\(key).\($0).medianMs"] } }
        let queryMemory = [r["text.queried.peakFootprintMB"], r["text.loaded.footprintMB"]].compactMap { $0 }.max()
        let pictureMemory = [r["image.queried.peakFootprintMB"], r["image.attached.footprintMB"]].compactMap { $0 }.max()
        let warmPicture = [r["image.warm280.p95Ms"], r["image.warm140.p95Ms"]].compactMap { $0 }.max()
        func check(_ value: Double?, _ limit: Double) -> Bool? { value.map { $0 <= limit } }
        return [
            Gate(name: "Warm text query (p95)", measured: "p95 \(ms(r["text.queryP95Ms"])), median \(ms(r["text.queryMedianMs"]))",
                 limit: "≤ 150 ms", passed: check(r["text.queryP95Ms"], 150)),
            Gate(name: "Encoder cold start", measured: seconds(r["text.coldStartSeconds"]), limit: "≤ 2 s",
                 passed: check(r["text.coldStartSeconds"], 2)),
            Gate(name: "Query-encoder memory (peak)", measured: mb(queryMemory), limit: "≤ 600 MB",
                 passed: check(queryMemory, 600)),
            Gate(name: "One image embed (worst median)", measured: ms(images.max()), limit: "≤ 1,500 ms",
                 passed: images.count == 4 ? check(images.max(), 1500) : nil),
            Gate(name: "Indexer memory (peak)", measured: mb(r["full.worked.peakFootprintMB"]), limit: "≤ 2,000 MB",
                 passed: check(r["full.worked.peakFootprintMB"], 2000)),
            Gate(name: "Warm picture query (p95)", measured: ms(warmPicture), limit: "≤ 600 ms",
                 passed: check(warmPicture, 600)),
            Gate(name: "Cold picture search", measured: seconds(r["image.coldSeconds"]), limit: "≤ 2.5 s",
                 passed: check(r["image.coldSeconds"], 2.5)),
            Gate(name: "Query service with pictures", measured: mb(pictureMemory), limit: "≤ 1,000 MB",
                 passed: check(pictureMemory, 1000)),
            Gate(name: "Every reference cosine", measured: r["reference.lowestCosine"].map { String(format: "lowest %.6f", $0) } ?? "–",
                 limit: "≥ 0.99", passed: hasReferences ? r["reference.passed"].map { $0 == 1 } : nil),
        ]
    }

    /// Runs this executable with `arguments`, echoing its output except the `RESULT` lines, which it returns.
    private static func child(_ arguments: [String]) throws -> (results: [String: Double], status: Int32) {
        guard let executable = Bundle.main.executableURL else { throw BenchFailure("can't find this executable") }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (BenchResults.parse(String(decoding: output, as: UTF8.self)), process.terminationStatus)
    }

    private static func memoryRows(_ r: [String: Double], _ stage: String, _ label: String) {
        row("footprint \(label) (peak so far)",
            "\(mb(r["\(stage).footprintMB"])) (\(mb(r["\(stage).peakFootprintMB"])))")
        row("resident / Metal allocated \(label)", "\(mb(r["\(stage).residentMB"])) / \(mb(r["\(stage).metalMB"]))")
    }

    private static func row(_ label: String, _ value: String) { print("  \(pad(label, 58)) \(value)") }
    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }
    private static func seconds(_ value: Double?) -> String { value.map { String(format: "%.2f s", $0) } ?? "–" }
    private static func ms(_ value: Double?) -> String { value.map { String(format: "%.1f ms", $0) } ?? "–" }
    private static func mb(_ value: Double?) -> String { value.map { String(format: "%.0f MB", $0) } ?? "–" }
    private static func int(_ value: Double?) -> String { value.map { String(Int($0.rounded())) } ?? "–" }

    private static func sysctl(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "unknown CPU" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "unknown CPU" }
        return String(cString: buffer)
    }
}
