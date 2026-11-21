import Foundation

/// `LookoutBench clicks`: what the developer click log (`LookoutClickRecord`, DEE-166) says about real searches, and
/// where Lookout falls short.
///
/// - How often an opened Lookout hit was first, in the top five, strong or weak: real-use MRR.
/// - Files opened from Spotlight's names: whether Lookout listed them too and where; the ones it missed are gaps.
/// - Searches that ended with nothing opened: queries Lookout may have failed.
/// - Opens before the meaning pass arrived: the keyword pass was all that was seen.
enum ClicksCommand {
    static func run(logs: [URL], show: Int) throws {
        let records = try load(logs)
        guard !records.isEmpty else { throw BenchFailure("no lines in \(logs.map(\.path).joined(separator: ", "))") }
        let opens = records.filter { $0.opened != nil }
        let lookoutOpens = opens.filter { $0.opened?.source == "lookout" }
        let nameOpens = opens.filter { $0.opened?.source == "name" }
        let ended = records.filter { $0.opened == nil }
        let first = records.map(\.at).min()!, last = records.map(\.at).max()!
        print("\(records.count) searches from \(first.formatted(date: .abbreviated, time: .shortened)) to "
              + "\(last.formatted(date: .abbreviated, time: .shortened)), apps \(Set(records.map(\.app)).sorted())")
        print("  \(lookoutOpens.count) opened a Lookout hit, \(nameOpens.count) a name result, \(ended.count) nothing")

        if !lookoutOpens.isEmpty {
            let ranks = lookoutOpens.compactMap { $0.opened?.rank }
            let n = Double(ranks.count)
            let strong = lookoutOpens.filter { record in
                record.lookout.first { $0.path == record.opened?.path }?.section == "strong"
            }.count
            print("\nLookout hits opened:")
            print(String(format: "  MRR %.3f, first %.0f%%, top five %.0f%%, strong %.0f%%, before meaning arrived %.0f%%",
                         ranks.reduce(0) { $0 + 1 / Double($1) } / n, 100 * Double(ranks.filter { $0 == 1 }.count) / n,
                         100 * Double(ranks.filter { $0 <= 5 }.count) / n, 100 * Double(strong) / n,
                         100 * Double(lookoutOpens.filter { $0.phase != "done" }.count) / n))
            let low = lookoutOpens.filter { ($0.opened?.rank ?? 0) > 3 }.sorted { $0.at > $1.at }
            if !low.isEmpty, show > 0 {
                print("  opened from below the top three:")
                for record in low.prefix(show) { print("    [\(record.opened!.rank)] \"\(record.query)\" → \(name(record.opened!.path))") }
            }
        }
        if !nameOpens.isEmpty {
            let listed = nameOpens.filter { $0.opened?.lookoutRank != nil }
            print("\nName results opened: Lookout listed \(listed.count) of \(nameOpens.count)")
            let missed = nameOpens.filter { $0.opened?.lookoutRank == nil }.sorted { $0.at > $1.at }
            if !missed.isEmpty, show > 0 {
                print("  not in Lookout's results (check whether they're indexed, and why they didn't qualify):")
                for record in missed.prefix(show) { print("    \"\(record.query)\" → \(record.opened!.path)") }
            }
            let below = listed.filter { ($0.opened?.lookoutRank ?? 0) > 3 }
            if !below.isEmpty, show > 0 {
                print("  in Lookout's results, but below the top three:")
                for record in below.prefix(show) {
                    print("    [\(record.opened!.lookoutRank!)] \"\(record.query)\" → \(name(record.opened!.path))")
                }
            }
        }
        if !ended.isEmpty, show > 0 {
            print("\nended with nothing opened (latest first):")
            for record in ended.sorted(by: { $0.at > $1.at }).prefix(show) {
                let top = record.lookout.prefix(3).map { name($0.path) }.joined(separator: " | ")
                print("    \"\(record.query)\" (\(record.lookout.count) hits, \(record.phase)) → \(top.isEmpty ? "nothing" : top)")
            }
        }
    }

    /// Every line of the logs, oldest first; lines that don't decode are counted and skipped.
    static func load(_ logs: [URL]) throws -> [LookoutClickRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var records: [LookoutClickRecord] = [], skipped = 0
        for log in logs {
            for line in try String(contentsOf: log, encoding: .utf8).split(separator: "\n") where !line.isEmpty {
                if let record = try? decoder.decode(LookoutClickRecord.self, from: Data(line.utf8)) {
                    records.append(record)
                } else {
                    skipped += 1
                }
            }
        }
        if skipped > 0 { print("skipped \(skipped) lines that don't decode") }
        return records.sorted { $0.at < $1.at }
    }

    private static func name(_ path: String) -> String { (path as NSString).lastPathComponent }
}
