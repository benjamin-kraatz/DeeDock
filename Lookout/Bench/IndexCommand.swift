import Foundation

/// `LookoutBench index`: what the index service does for one sync, in this process and without XPC: check the model,
/// prune, sync the roots, index everything pending (no power policy), then finish long files. Prints each file, the
/// counts and the timings, and the peak memory.
///
/// The index goes in `--index`, never in the app's folder unless that's what's passed. llama.cpp's warnings go to
/// stderr.
enum IndexCommand {
    static func run(models: URL, index: URL, roots: [URL], excluded: [URL]) throws {
        guard !roots.isEmpty else { throw BenchFailure("missing --root <folder>") }
        let total = DispatchTime.now().uptimeNanoseconds
        let store = try IndexStore(directory: index)
        var options = IndexOptions()
        options.excludedFolders = excluded.map(\.path)
        var modelSeconds: Double?
        let indexer = try Indexer(store: store, options: options) {
            let (embedder, seconds) = try Stopwatch.time {
                try LlamaEmbedder(models: LlamaModels.locate(in: models), textOnly: false)
            }
            modelSeconds = seconds
            return embedder
        }
        defer { indexer.finish() }
        indexer.embedderSource = LlamaEmbedder.modelInfo.vectorSource
        indexer.resetOnModelChange = { indexed, now in print("model changed, indexing again:\n  was \(indexed)\n  now \(now)") }
        try indexer.checkModel()

        // The service's rules: folders Lookout never reads are refused, and their files leave the index.
        let checked = Rules.checkRoots(roots.map(\.path))
        for refused in checked.refused { print("refused (\(refused.refusal.reason)): \(refused.path)") }
        let realRoots = checked.allowed.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let pruned = try store.prune(keepingUnder: realRoots.map(\.path))
        let availability = RootAvailability.check(realRoots)
        store.scope = availability.available.map(\.path)
        for path in availability.missing { print("missing: \(path)") }
        for path in availability.notPermitted { print("not permitted: \(path)") }

        let (summary, syncSeconds) = try Stopwatch.time { try indexer.sync(availability.available) }
        print("index: \(store.file.path)")
        print(String(format: "sync %.3f s: %d added, %d changed, %d moved, %d removed, %d unchanged, %d pruned",
                     syncSeconds, summary.added, summary.changed, summary.moved, summary.removed, summary.unchanged,
                     pruned))
        for (reason, count) in summary.crawl.skipped.sorted(by: { $0.key < $1.key }) {
            print("  skipped \(count) file\(count == 1 ? "" : "s"): \(reason)")
        }
        for (reason, count) in summary.crawl.skippedFolders.sorted(by: { $0.key < $1.key }) {
            print("  skipped \(count) folder\(count == 1 ? "" : "s"): \(reason)")
        }
        let lastUsed = summary.crawl.candidates.filter { $0.lastUsed != nil }.count
        print("  \(summary.crawl.candidates.count) candidates, \(lastUsed) with a Spotlight last-used date")

        let pending = try store.pendingCount()
        let (states, runSeconds) = try Stopwatch.time {
            try indexer.run(onEvent: { event in
                print(String(format: "  [%d/%d] %-10@ %-8@ %6.3f s  %@%@", event.done, event.total,
                             event.kind.rawValue, event.state, event.seconds,
                             (event.path as NSString).lastPathComponent, event.note.map { " (\($0))" } ?? ""))
            })
        }
        let (rest, restSeconds) = try Stopwatch.time {
            try indexer.finishLongFiles(onStep: { step in
                print("  later [\(step.done)/\(step.total)] \((step.path as NSString).lastPathComponent) \(step.state)")
            })
        }

        let counts = try store.counts()
        print("\nfirst pass: \(pending) files in \(String(format: "%.2f", runSeconds)) s "
              + "(model load \(modelSeconds.map { String(format: "%.2f s", $0) } ?? "–") included): \(describe(states))")
        if !rest.isEmpty { print("later pass: \(String(format: "%.2f", restSeconds)) s: \(describe(rest))") }
        let embedSeconds = runSeconds - (modelSeconds ?? 0)
        if pending > 0, embedSeconds > 0 {
            print(String(format: "throughput: %.2f files/s without the model load, %.2f with it",
                         Double(pending) / embedSeconds, Double(pending) / runSeconds))
        }
        for (kind, byState) in counts.byKindAndState.sorted(by: { $0.key < $1.key }) {
            print("  \(kind): \(describe(byState))")
        }
        print("vectors \(counts.vectors), segments \(counts.segments), unfinished \(counts.unfinished), "
              + "index \(ByteCountFormatter.string(fromByteCount: IndexStore.size(of: store.file), countStyle: .file))")
        if let memory = ProcessMemory.sample() {
            print(String(format: "memory: footprint %.0f MB, peak %.0f MB, Metal %.0f MB",
                         ProcessMemory.megabytes(memory.footprint), ProcessMemory.megabytes(memory.peakFootprint),
                         ProcessMemory.megabytes(memory.metalAllocated)))
        }
        print(String(format: "total %.2f s", Double(DispatchTime.now().uptimeNanoseconds - total) / 1e9))
    }

    private static func describe(_ states: [String: Int]) -> String {
        states.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ")
    }
}
