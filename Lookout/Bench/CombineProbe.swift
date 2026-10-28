import Foundation
import ImageIO

/// `LookoutBench combine`: searching with a picture and words together (DEE-126), measured on an index.
///
/// Each case is a picture, the words typed with it, and the files that answer it. The probe embeds both the way the
/// query service does and ranks the index's files three ways, at several weights for the words:
///
/// - `sum`: one query vector, the normalized weighted sum of the picture's and the words' vectors, scored as
///   `Searcher.meaning` scores any query. The alternative Lookout didn't take.
/// - `fuse`: each vector scored on its own scale, then blended as Lookout blends them (`Searcher.blend`).
/// - `fuse+words`: `fuse`, plus the typed words' keyword coverage as `Searcher.similar` adds it.
///
/// The file searched with never counts. A case's rank is that of its best answer, so R@1 is the share of cases whose
/// first result answers them. A table after the ranks says how many files pass the meaning gate on the blend's scale,
/// and how often an answer is among them.
///
/// The cases file is tab-separated: picture path, words, then one or more answers as file names or path suffixes.
/// Lines starting with `#` are skipped. With `--show <n>`, every case prints its top n at each method's best weight,
/// or at `--weight`. DEE-126's labeled cases came from macOS's wallpaper thumbnails
/// (`/System/Library/Desktop Pictures/.thumbnails`): Light and Dark pairs ("at night") and color families ("in orange"),
/// copied under neutral names so their file names don't give the answer away.
enum CombineProbe {
    static let weights: [Double] = [0, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 1]

    struct Case {
        let picture: URL
        let words: String
        let answers: [String]
    }

    static func run(models: URL, index: URL, cases file: URL, show: Int, weight shownWeight: Double?) throws {
        let cases = try load(file)
        guard !cases.isEmpty else { throw BenchFailure("no cases in \(file.path)") }
        guard let store = try IndexStore.openReadOnly(directory: index) else {
            throw BenchFailure("no index in \(index.path)")
        }
        let searcher = try Searcher(store: store)
        let paths = try searcher.files(withIDs: Set(searcher.rowFile)).mapValues(\.path)
        print("index: \(searcher.vectorCount) vectors, \(paths.count) files; \(cases.count) cases")

        let llama = try LlamaModels.locate(in: models)
        guard let media = llama.media else { throw BenchFailure("no \(ModelFiles.media.name) in the models folder") }
        let embedder = try LlamaEmbedder(models: llama, textOnly: true)
        defer { embedder.close() }
        try embedder.attachMedia(media)

        typealias Method = (name: String, rank: (Prepared, Double) -> [Int64])
        let methods: [Method] = [
            ("sum", { rankSum($0, $1, searcher) }),
            ("fuse", { rankFused($0, $1, searcher, words: false) }),
            ("fuse+words", { rankFused($0, $1, searcher, words: true) }),
        ]
        var prepared: [Prepared] = []
        for item in cases {
            guard let source = CGImageSourceCreateWithURL(item.picture as CFURL, nil) else {
                throw BenchFailure("can't read \(item.picture.path)")
            }
            let picture = try QueryPicture.make(from: source, screenshot: false)
            let pictureVector = try embedder.embedImage(pixels: [UInt8](picture.pixels), width: picture.width,
                                                        height: picture.height)
            let wordsVector = try embedder.embedTexts([Prompts.query(item.words)])[0]
            let own = Set(paths.filter { $0.value == item.picture.resolvingSymlinksInPath().path }.keys)
            let answers = Set(paths.filter { _, path in item.answers.contains { path.hasSuffix($0) } }.keys)
            if answers.isEmpty { print("warning: no answer in the index for \(item.picture.lastPathComponent)") }
            prepared.append(Prepared(item: item, picture: pictureVector, words: wordsVector, own: own,
                                     answers: answers, coverage: try coverage(item.words, searcher)))
        }

        print("\nmethod      weight   R@1    R@3    MRR")
        var bestWeight: [String: Double] = [:]
        for method in methods {
            var best = -1.0
            for weight in weights {
                let ranks = prepared.map { rank(of: $0.answers, in: method.rank($0, weight)) }
                let r1 = share(ranks) { $0 == 1 }, r3 = share(ranks) { $0 <= 3 }
                let mrr = ranks.reduce(0.0) { $0 + ($1 == .max ? 0 : 1 / Double($1)) } / Double(ranks.count)
                print(String(format: "%-11@ %5.2f   %5.2f  %5.2f  %5.3f", method.name, weight, r1, r3, mrr))
                if mrr > best { (best, bestWeight[method.name]) = (mrr, weight) }
            }
        }

        // How many files pass the meaning gate on the blend's scale, and how often an answer is among them.
        print("\nblend gate (z ≥ \(LookoutRanking.zGate)) weight  passing  answer passes")
        for weight in weights {
            var passing = 0.0, answered = 0.0
            for item in prepared {
                let z = blended(item, weight, searcher)
                var best: [Int64: Double] = [:]
                for row in z.indices where !item.own.contains(searcher.rowFile[row]) {
                    best[searcher.rowFile[row]] = max(best[searcher.rowFile[row]] ?? -.infinity, z[row])
                }
                let passed = best.filter { $0.value >= LookoutRanking.zGate }
                passing += Double(passed.count)
                if passed.keys.contains(where: item.answers.contains) { answered += 1 }
            }
            print(String(format: "                         %5.2f  %7.1f  %5.2f", weight,
                         passing / Double(prepared.count), answered / Double(prepared.count)))
        }

        guard show > 0 else { return }
        for item in prepared {
            print("\n\(item.item.picture.lastPathComponent) + \"\(item.item.words)\"")
            for method in methods {
                let weight = shownWeight ?? bestWeight[method.name] ?? 0.5
                let top = method.rank(item, weight).prefix(show).map { file in
                    (item.answers.contains(file) ? "*" : "") + ((paths[file] ?? "?") as NSString).lastPathComponent
                }
                print(String(format: "  %-11@ %.1f  ", method.name, weight) + top.joined(separator: " | "))
            }
        }
    }

    struct Prepared {
        let item: Case
        let picture: [Float]
        let words: [Float]
        let own: Set<Int64>
        let answers: Set<Int64>
        let coverage: [Int64: Double]
    }

    /// Files best first by their best segment's score, without the file searched with.
    private static func ranked(_ scores: [Double], _ searcher: Searcher, excluding: Set<Int64>) -> [Int64] {
        var best: [Int64: Double] = [:]
        for row in scores.indices where !excluding.contains(searcher.rowFile[row]) {
            best[searcher.rowFile[row]] = max(best[searcher.rowFile[row]] ?? -.infinity, scores[row])
        }
        return best.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }.map(\.key)
    }

    private static func meaning(_ vector: [Float], _ searcher: Searcher) -> [Double] {
        Searcher.meaning(searcher.score(vector), searcher.rowModality, setsScale: searcher.rowSetsScale)
    }

    private static func rankSum(_ item: Prepared, _ weight: Double, _ searcher: Searcher) -> [Int64] {
        var vector = zip(item.picture, item.words).map { Float(1 - weight) * $0 + Float(weight) * $1 }
        let norm = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        vector = vector.map { $0 / max(norm, 1e-6) }
        return ranked(meaning(vector, searcher), searcher, excluding: item.own)
    }

    /// Both vectors' meaning scores blended as `Searcher.similar` blends them.
    private static func blended(_ item: Prepared, _ weight: Double, _ searcher: Searcher) -> [Double] {
        Searcher.blend(meaning(item.picture, searcher), meaning(item.words, searcher), weight: weight,
                       setsScale: searcher.rowSetsScale)
    }

    private static func rankFused(_ item: Prepared, _ weight: Double, _ searcher: Searcher, words: Bool) -> [Int64] {
        let fused = blended(item, weight, searcher).enumerated().map { row, z in
            words ? max(z, 0) + LookoutRanking.wordWeight
                * pow(item.coverage[searcher.rowFile[row]] ?? 0, LookoutRanking.coverageExponent) : z
        }
        return ranked(fused, searcher, excluding: item.own)
    }

    /// The share of the typed words each file contains, as `Searcher.similar` counts it.
    private static func coverage(_ words: String, _ searcher: Searcher) throws -> [Int64: Double] {
        let terms = Searcher.terms(words).filter { !Searcher.pictureConnectors.contains($0) }
        let patterns = Searcher.patterns(terms, prefixLast: false)
        var coverage: [Int64: Double] = [:]
        for pattern in patterns {
            try searcher.store.db.query("""
                SELECT DISTINCT s.file FROM fts JOIN segments s ON s.id = fts.rowid WHERE fts MATCH ?
                """, [.text(pattern)]) { coverage[$0.int(0), default: 0] += 1 / Double(patterns.count) }
        }
        return coverage
    }

    private static func rank(of answers: Set<Int64>, in ranking: [Int64]) -> Int {
        (ranking.firstIndex(where: answers.contains).map { $0 + 1 }) ?? .max
    }

    private static func share(_ ranks: [Int], _ hit: (Int) -> Bool) -> Double {
        Double(ranks.filter(hit).count) / Double(max(ranks.count, 1))
    }

    private static func load(_ file: URL) throws -> [Case] {
        let base = file.deletingLastPathComponent()
        return try String(contentsOf: file, encoding: .utf8).split(separator: "\n").compactMap { line in
            guard !line.hasPrefix("#"), !line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3 else { throw BenchFailure("a case needs a picture, words and an answer: \(line)") }
            let path = (fields[0] as NSString).expandingTildeInPath
            let picture = path.hasPrefix("/") ? URL(fileURLWithPath: path) : base.appendingPathComponent(path)
            return Case(picture: picture, words: fields[1], answers: Array(fields[2...]).filter { !$0.isEmpty })
        }
    }
}
