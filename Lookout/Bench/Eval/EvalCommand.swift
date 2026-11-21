import Foundation

/// `LookoutBench eval`: known-item search quality and speed on an index, the way the app searches it.
///
/// Every case runs both of the app's passes (`LookoutSearch.run`): the keyword-only first pass (no vector, last word as
/// a prefix), then the hybrid pass with the query's vector. A case's rank is its best answer's place in the hybrid
/// results, files and folders together as the list shows them, within the app's limit of 40; past that it's a miss.
/// `fMRR` ranks the files alone, to tell folder results pushing an answer down from the answer ranking badly.
///
/// The report groups cases by source, language, style, the answer's kind and how much the query copies its file
/// (`EvalCase.overlap`), and prints the time each pass took. `--json` also writes every case's outcome, so two runs
/// can be compared case by case.
enum EvalCommand {
    /// The app's result limit (`LookoutSearchRequest.limit`).
    static let limit = 40

    struct Outcome: Codable {
        let q: String
        let lang: String
        let style: String
        let source: String
        let split: String
        let kind: String
        let overlap: Double?
        /// 1-based place of the best answer in the hybrid results, nil when it isn't among them.
        let rank: Int?
        /// The same among the hybrid results' files only, as if there were no folder results.
        let fileRank: Int?
        /// The same in the keyword-only first pass.
        let keywordRank: Int?
        /// The best answer is among the strong results (not folded under "Weaker matches").
        let strong: Bool
        /// How many results the hybrid pass returned, strong and in all.
        let strongCount: Int
        let count: Int
        let embedMilliseconds: Double
        let keywordMilliseconds: Double
        let hybridMilliseconds: Double
        /// The top three results' file names, for reading misses.
        let top: [String]
    }

    static func run(models: URL, index: URL, cases files: [URL], split: String?, drop: [String], sets: [String],
                    show: Int, json: URL?) throws {
        guard !files.isEmpty else { throw BenchFailure("missing --cases <file>") }
        var cases = try EvalCase.load(files)
        if let split, split != "all" { cases = cases.filter { $0.split == split } }
        if !drop.isEmpty { cases = cases.filter { item in !item.expect.contains { path in drop.contains(where: path.contains) } } }
        guard !cases.isEmpty else { throw BenchFailure("no cases") }
        guard let store = try IndexStore.openReadOnly(directory: index) else {
            throw BenchFailure("no index in \(index.path)")
        }
        let (searcher, loadSeconds) = try Stopwatch.time { try Searcher(store: store) }
        searcher.tuning = try searcher.tuning.overridden(sets)
        // Relative dates in the queries were written against the day the cases were made.
        searcher.referenceDate = cases.lazy.compactMap(\.asOf).first.flatMap(ISO8601DateFormatter.day.date(from:))
        if !sets.isEmpty { print("tuning: " + sets.joined(separator: ", ")) }
        let byPath = try indexedFiles(store)
        let copies = try sameText(store)
        print("index: \(searcher.vectorCount) vectors, \(byPath.count) files (vectors loaded in "
              + String(format: "%.2f s", loadSeconds) + "); \(cases.count) cases")

        let embedder = try LlamaEmbedder(models: LlamaModels.locate(in: models), textOnly: true)
        defer { embedder.close() }
        _ = try embedder.embedTexts([Prompts.query("warm up")])

        var outcomes: [Outcome] = []
        var unanswerable = 0
        for item in cases {
            let expected = Set(item.expect.compactMap { byPath[realPath($0)]?.id })
            // A copy of an answer (the same invoice saved twice) answers the query as well.
            let answers = expected.reduce(into: expected) { all, id in all.formUnion(copies[id] ?? []) }
            guard !answers.isEmpty else {
                unanswerable += 1
                if unanswerable <= 10 { print("not in the index: \(item.expect.first ?? "?") (\(item.q))") }
                continue
            }
            let answerKind = item.expect.lazy.compactMap { byPath[realPath($0)]?.kind }.first ?? "?"
            let (vector, embedSeconds) = try Stopwatch.time { try embedder.embedTexts([Prompts.query(item.q)])[0] }
            let (keyword, keywordSeconds) = try Stopwatch.time {
                try searcher.search(item.q, queryVector: nil, limit: limit, prefixLast: true)
            }
            let (hybrid, hybridSeconds) = try Stopwatch.time {
                try searcher.search(item.q, queryVector: vector, limit: limit, prefixLast: false)
            }
            let ids = { (results: LookoutResultSet) in results.all.map { byPath[$0.path]?.id ?? -1 } }
            let rank = ids(hybrid).firstIndex(where: answers.contains).map { $0 + 1 }
            let fileRank = hybrid.all.filter { !$0.isFolder }.map { byPath[$0.path]?.id ?? -1 }
                .firstIndex(where: answers.contains).map { $0 + 1 }
            outcomes.append(Outcome(
                q: item.q, lang: item.lang, style: item.style, source: item.source, split: item.split,
                kind: answerKind, overlap: item.overlap, rank: rank, fileRank: fileRank,
                keywordRank: ids(keyword).firstIndex(where: answers.contains).map { $0 + 1 },
                strong: rank.map { $0 <= hybrid.strong.count } ?? false,
                strongCount: hybrid.strong.count, count: hybrid.count,
                embedMilliseconds: embedSeconds * 1000, keywordMilliseconds: keywordSeconds * 1000,
                hybridMilliseconds: hybridSeconds * 1000,
                top: hybrid.all.prefix(3).map { ($0.path as NSString).lastPathComponent }))
        }
        if unanswerable > 0 { print("\(unanswerable) cases skipped: their answer isn't in the index") }

        report(outcomes)
        if show > 0 { printMisses(outcomes, count: show) }
        if let json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(outcomes).write(to: json)
            print("\nwrote \(outcomes.count) outcomes to \(json.path)")
        }
    }

    // MARK: Report

    private static func report(_ outcomes: [Outcome]) {
        print("\ngroup                     n     MRR    R@1    R@5   R@40  strong  kwMRR  fMRR   empty  strong/q")
        row("all", outcomes)
        let groups: [(String, (Outcome) -> String)] = [
            ("source", \.source), ("lang", \.lang), ("style", \.style), ("kind", \.kind),
            ("overlap", { overlapBucket($0.overlap) }), ("lang×style", { "\($0.lang) \($0.style)" }),
        ]
        for (name, key) in groups {
            print("\(name):")
            for (value, members) in Dictionary(grouping: outcomes, by: key).sorted(by: { $0.key < $1.key }) {
                row("  " + value, members)
            }
        }

        print("\ntime per query      p50 ms   p95 ms   max ms")
        for (name, values) in [("embed", outcomes.map(\.embedMilliseconds)),
                               ("keyword pass", outcomes.map(\.keywordMilliseconds)),
                               ("hybrid pass", outcomes.map(\.hybridMilliseconds))] {
            let samples = Samples(values)
            print("  " + name.padding(toLength: 16, withPad: " ", startingAt: 0)
                  + String(format: " %7.1f  %7.1f  %7.1f", samples.median, samples.percentile(95),
                         samples.max))
        }
    }

    private static func row(_ name: String, _ members: [Outcome]) {
        let n = Double(members.count)
        let mrr = members.reduce(0.0) { $0 + ($1.rank.map { 1 / Double($0) } ?? 0) } / n
        let keywordMRR = members.reduce(0.0) { $0 + ($1.keywordRank.map { 1 / Double($0) } ?? 0) } / n
        let fileMRR = members.reduce(0.0) { $0 + ($1.fileRank.map { 1 / Double($0) } ?? 0) } / n
        let share = { (test: (Outcome) -> Bool) in Double(members.filter(test).count) / n }
        let strongPerQuery = members.reduce(0.0) { $0 + Double($1.strongCount) } / n
        let label = name.count < 22 ? name + String(repeating: " ", count: 22 - name.count) : name
        print(label + String(format: " %5d   %5.3f  %5.2f  %5.2f  %5.2f  %5.2f   %5.3f  %5.3f  %5.2f  %6.1f", members.count,
                     mrr, share { $0.rank == 1 }, share { ($0.rank ?? .max) <= 5 }, share { $0.rank != nil },
                     share(\.strong), keywordMRR, fileMRR, share { $0.count == 0 }, strongPerQuery))
    }

    private static func overlapBucket(_ overlap: Double?) -> String {
        guard let overlap else { return "unknown" }
        switch overlap {
        case ..<0.34: return "low (<⅓)"
        case ..<0.67: return "mid"
        default: return "high (≥⅔)"
        }
    }

    private static func printMisses(_ outcomes: [Outcome], count: Int) {
        let misses = outcomes.filter { ($0.rank ?? .max) > 1 }.sorted { ($0.rank ?? .max) > ($1.rank ?? .max) }
        print("\nmisses (\(misses.count), showing \(min(count, misses.count))):")
        for miss in misses.prefix(count) {
            print("  [\(miss.rank.map(String.init) ?? "–")] \(miss.lang) \(miss.style) \"\(miss.q)\" → "
                  + miss.top.joined(separator: " | "))
        }
    }

    // MARK: Index

    /// Every searchable file in the index by its path: its id and kind.
    static func indexedFiles(_ store: IndexStore) throws -> [String: (id: Int64, kind: String)] {
        var files: [String: (id: Int64, kind: String)] = [:]
        try store.db.query("SELECT id, path, kind FROM files WHERE state IN ('done', 'partial')") { row in
            files[row.text(1) ?? ""] = (row.int(0), row.text(2) ?? "?")
        }
        return files
    }

    /// For every file whose text another file has too, those other files: copies, which answer the same queries.
    /// Files without text (pictures) have no copies here.
    static func sameText(_ store: IndexStore) throws -> [Int64: Set<Int64>] {
        var text: [Int64: String] = [:]
        try store.db.query("""
            SELECT s.file, fts.body FROM segments s JOIN fts ON fts.rowid = s.id
            WHERE s.kind IN ('page', 'chunk', 'ocr') ORDER BY s.file, s.id
            """) { row in text[row.int(0), default: ""] += row.text(1) ?? "" }
        let groups = Dictionary(grouping: text.filter { !$0.value.isEmpty }.keys) { text[$0]! }.values.filter { $0.count > 1 }
        var copies: [Int64: Set<Int64>] = [:]
        for group in groups {
            for file in group { copies[file] = Set(group).subtracting([file]) }
        }
        return copies
    }

    /// A path as the index stores it: `~` expanded, standardized, real (/private/var, not /var).
    static func realPath(_ path: String) -> String {
        FolderSelection.realPath(((path as NSString).expandingTildeInPath as NSString).standardizingPath)
    }
}
