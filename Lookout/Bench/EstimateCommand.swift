import Foundation

/// `LookoutBench estimate`: what onboarding will show for each folder: how many files of each kind, how long the
/// first pass takes, and how big the index gets, with the subfolders one level down. Reads metadata only.
enum EstimateCommand {
    static func run(roots: [URL]) throws {
        guard !roots.isEmpty else { throw BenchFailure("missing --root <folder>") }
        let options = IndexOptions()
        for root in roots {
            let (crawl, crawlSeconds) = Stopwatch.time {
                Crawler.crawl([root], options: options, readsLastUsed: false)
            }
            let (estimate, estimateSeconds) = Stopwatch.time { Estimator.estimate(crawl.candidates, options: options) }
            print("\(root.path)  (crawl \(String(format: "%.3f", crawlSeconds)) s, "
                  + "estimate \(String(format: "%.3f", estimateSeconds)) s)")
            print("  " + describe(estimate))
            let skipped = crawl.skipped.values.reduce(0, +)
            if skipped > 0 { print("  skipped \(skipped) files, \(crawl.skippedFolders.values.reduce(0, +)) folders") }
            let subfolders = Estimator.estimates(bySubfolder: crawl.candidates, of: root.path, options: options)
            for (folder, part) in subfolders.sorted(by: { $0.value.seconds > $1.value.seconds }) where folder != root.path {
                print("    \((folder as NSString).lastPathComponent): " + describe(part))
            }
        }
    }

    private static func describe(_ estimate: Estimator.Estimate) -> String {
        let kinds = FileKind.allCases.compactMap { kind in estimate.files[kind].map { "\($0) \(kind.rawValue)" } }
        var line = "\(estimate.fileCount) files"
        if !kinds.isEmpty { line += " (" + kinds.joined(separator: ", ") + ")" }
        line += String(format: ", first pass ≈ %.0f s", estimate.seconds)
        if estimate.longFiles > 0 {
            line += String(format: ", %d long files ≈ %.0f s later", estimate.longFiles, estimate.laterSeconds)
        }
        return line + ", index ≈ " + ByteCountFormatter.string(fromByteCount: Int64(estimate.bytes), countStyle: .file)
    }
}
