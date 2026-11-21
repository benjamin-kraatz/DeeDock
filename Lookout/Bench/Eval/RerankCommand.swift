import CreateML
import Foundation
import TabularData

/// `LookoutBench rerank`: a probe of a learned reranker over Lookout's results (DEE-166).
///
/// Every case runs the app's hybrid search (`Searcher`, today's ranking). Each of its up to 40 hits becomes a row of
/// features (`LookoutRerankFeatures`) labeled 1 when it answers the case. A boosted-tree model learns from the tuning half,
/// then reorders the held-out half's hits by its prediction; the report compares the two orders the way `eval`
/// does, and how well the prediction would split strong from weak results.
///
/// It's a probe: the model learns from generated queries, so it can learn their habits as well as what makes a hit
/// right. `--out` saves it as a Core ML model for a closer look.
enum RerankCommand {
    /// - Parameters:
    ///   - kind: `linear` (pairwise, `PairwiseLinearRanker`) or `tree` (Create ML's boosted trees, pointwise).
    ///   - depth: The trees' depth.
    ///   - rounds: How many trees.
    ///   - clicks: Click logs (`LookoutClickRecord`) whose searches join the training half: each search where the
    ///     opened file was among Lookout's hits, labeled by what was opened.
    static func run(models: URL, index: URL, cases files: [URL], drop: [String], kind: String, depth: Int, rounds: Int,
                    clicks: [URL], out: URL?, show: Int) throws {
        var cases = try EvalCase.load(files)
        if !drop.isEmpty { cases = cases.filter { item in !item.expect.contains { path in drop.contains(where: path.contains) } } }
        guard let store = try IndexStore.openReadOnly(directory: index) else { throw BenchFailure("no index in \(index.path)") }
        let searcher = try Searcher(store: store)
        let now = cases.lazy.compactMap(\.asOf).first.flatMap(ISO8601DateFormatter.day.date(from:)) ?? Date()
        searcher.referenceDate = now
        let byPath = try EvalCommand.indexedFiles(store)
        let copies = try EvalCommand.sameText(store)
        let embedder = try LlamaEmbedder(models: LlamaModels.locate(in: models), textOnly: true)
        defer { embedder.close() }

        // Every case's hits as feature rows.
        var queries: [Query] = []
        for (number, item) in cases.enumerated() {
            let expected = Set(item.expect.compactMap { byPath[EvalCommand.realPath($0)]?.id })
            guard !expected.isEmpty else { continue }
            let answers = expected.reduce(into: expected) { $0.formUnion(copies[$1] ?? []) }
            let vector = try embedder.embedTexts([Prompts.query(item.q)])[0]
            let results = try searcher.search(item.q, queryVector: vector, limit: EvalCommand.limit, prefixLast: false)
            let hits = results.all
            let features = LookoutRerankFeatures.rows(query: item.q, hits: hits, isLookup: results.isLookup, now: now)
            queries.append(Query(item: item, names: hits.map { ($0.path as NSString).lastPathComponent },
                                 labels: hits.map { answers.contains(byPath[$0.path]?.id ?? -1) },
                                 features: features))
            if (number + 1) % 500 == 0 { print("  \(number + 1)/\(cases.count) cases searched") }
        }
        var tune = queries.filter { $0.item.split == "tune" }
        let held = queries.filter { $0.item.split == "held" }
        if !clicks.isEmpty {
            let logged = try ClicksCommand.load(clicks).compactMap { record -> Query? in
                guard let opened = record.opened, opened.lookoutRank != nil,
                      record.featureVersion == LookoutRerankFeatures.version else { return nil }
                return Query(item: EvalCase(q: record.query, expect: [opened.path], lang: "?", style: "click",
                                            source: "click", split: "tune"),
                             names: record.lookout.map { ($0.path as NSString).lastPathComponent },
                             labels: record.lookout.map { $0.path == opened.path }, features: record.lookout.map(\.features))
            }
            print("\(logged.count) logged searches join the training half")
            tune += logged
        }
        print("\(tune.count) tuning and \(held.count) held-out cases, \(tune.reduce(0) { $0 + $1.labels.count }) training rows")

        // Train on the tuning half, then score the held-out half's hits.
        let predictions: [Double]
        var tree: MLBoostedTreeRegressor?
        let start = DispatchTime.now().uptimeNanoseconds
        switch kind {
        case "tree":
            let model = try MLBoostedTreeRegressor(
                trainingData: frame(tune), targetColumn: "label",
                parameters: .init(maxDepth: depth, maxIterations: rounds, minLossReduction: 0, minChildWeight: 5,
                                  randomSeed: 7, stepSize: 0.1, earlyStoppingRounds: nil, rowSubsample: 0.8,
                                  columnSubsample: 0.8))
            print(String(format: "trained in %.1f s", Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9))
            let (column, seconds) = try Stopwatch.time { try model.predictions(from: frame(held)) }
            predictions = (0..<column.count).map { column[$0] as? Double ?? 0 }
            print(String(format: "predicting took %.3f ms a query", seconds * 1000 / Double(max(held.count, 1))))
            tree = model
        case "linear":
            let ranker = PairwiseLinearRanker(queries: tune.map { ($0.features, $0.labels) })
            print(String(format: "trained in %.1f s", Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9))
            predictions = held.flatMap { $0.features.map(ranker.score) }
            print("weights (per standard deviation), largest first:")
            for (name, weight) in zip(LookoutRerankFeatures.names, ranker.weights).sorted(by: { abs($0.1) > abs($1.1) }) {
                print(String(format: "  %+.3f  %@", weight, name))
            }
        default:
            throw BenchFailure("--model \(kind): tree or linear")
        }
        var offset = 0
        var outcomes: [(query: Query, base: Int?, reranked: Int?, scores: [Double])] = []
        for query in held {
            let scores = Array(predictions[offset..<offset + query.labels.count])
            offset += query.labels.count
            let order = query.labels.indices.sorted { scores[$0] > scores[$1] }
            outcomes.append((query, query.labels.firstIndex(of: true).map { $0 + 1 },
                             order.firstIndex { query.labels[$0] }.map { $0 + 1 }, scores))
        }

        report(outcomes.map { Ranks(item: $0.query.item, base: $0.base, reranked: $0.reranked) })
        if kind == "tree" { strongCuts(outcomes.map { ($0.scores, $0.query.labels) }) }
        if show > 0 {
            print("\nheld-out cases the reranker changed most:")
            let changed = outcomes.filter { $0.base != $0.reranked }
                .sorted { abs(($0.base ?? 41) - ($0.reranked ?? 41)) > abs(($1.base ?? 41) - ($1.reranked ?? 41)) }
            for outcome in changed.prefix(show) {
                let top = outcome.query.labels.indices.sorted { outcome.scores[$0] > outcome.scores[$1] }.first
                print("  \(outcome.base.map(String.init) ?? "–") → \(outcome.reranked.map(String.init) ?? "–")  "
                      + "\(outcome.query.item.lang) \"\(outcome.query.item.q)\"  now first: "
                      + (top.map { outcome.query.names[$0] } ?? "–"))
            }
        }
        if let out, let model = tree {
            try model.write(to: out, metadata: .init(author: "LookoutBench", shortDescription:
                "Lookout reranker probe (DEE-166): the chance a hit answers its query", version: "probe"))
            print("\nwrote \(out.path)")
        }
    }

    struct Query {
        let item: EvalCase
        let names: [String]
        let labels: [Bool]
        let features: [[Double]]
    }

    private static func frame(_ queries: [Query]) throws -> DataFrame {
        var frame = DataFrame()
        let rows = queries.flatMap { zip($0.features, $0.labels) }
        for (index, name) in LookoutRerankFeatures.names.enumerated() {
            frame.append(column: Column(name: name, contents: rows.map { $0.0[index] }))
        }
        frame.append(column: Column(name: "label", contents: rows.map { $0.1 ? 1.0 : 0.0 }))
        return frame
    }

    /// One held-out case's answer rank in today's order and in the reranked one.
    struct Ranks {
        let item: EvalCase
        let base: Int?
        let reranked: Int?
    }

    private static func report(_ outcomes: [Ranks]) {
        print("\nheld-out half          n   MRR before → after   R@1 before → after   R@5 before → after")
        func mrr(_ members: [Ranks], _ rank: (Ranks) -> Int?) -> Double {
            members.reduce(0.0) { $0 + (rank($1).map { 1 / Double($0) } ?? 0) } / Double(members.count)
        }
        func share(_ members: [Ranks], _ test: (Ranks) -> Bool) -> Double {
            Double(members.filter(test).count) / Double(members.count)
        }
        func row(_ name: String, _ members: [Ranks]) {
            print(name.padding(toLength: 20, withPad: " ", startingAt: 0)
                  + String(format: " %5d   %.3f → %.3f       %.2f → %.2f         %.2f → %.2f", members.count,
                           mrr(members, \.base), mrr(members, \.reranked),
                           share(members) { $0.base == 1 }, share(members) { $0.reranked == 1 },
                           share(members) { ($0.base ?? 99) <= 5 }, share(members) { ($0.reranked ?? 99) <= 5 }))
        }
        row("all", outcomes)
        let groups: [(String, (Ranks) -> String)] = [("lang", \.item.lang), ("source", \.item.source),
                                                     ("style", \.item.style)]
        for (name, key) in groups {
            print("\(name):")
            for (value, members) in Dictionary(grouping: outcomes, by: key).sorted(by: { $0.key < $1.key })
            where members.count >= 5 {
                row("  " + value, members)
            }
        }
    }

    /// How a probability cut would split strong from weak: the answer's share among the strong ones, and how many.
    private static func strongCuts(_ queries: [(scores: [Double], labels: [Bool])]) {
        print("\nstrong = predicted ≥ t    answer strong   strong per query")
        for threshold in [0.05, 0.1, 0.2, 0.3, 0.5] {
            var answered = 0.0, strong = 0.0
            for query in queries {
                let kept = query.scores.indices.filter { query.scores[$0] >= threshold }
                // The best hit stays strong whatever its score, as the ratio cut keeps the top one.
                let best = query.scores.indices.max { query.scores[$0] < query.scores[$1] }
                let set = Set(kept + (best.map { [$0] } ?? []))
                strong += Double(set.count)
                if set.contains(where: { query.labels[$0] }) { answered += 1 }
            }
            let n = Double(max(queries.count, 1))
            print(String(format: "  t = %.2f                %.2f            %.1f", threshold, answered / n, strong / n))
        }
    }
}
