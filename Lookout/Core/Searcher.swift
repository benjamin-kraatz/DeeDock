// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

import Foundation

/// Hybrid search over the index: meaning (EmbeddingGemma 2's vectors) and words (FTS5).
///
/// Meaning is the model's cosine similarity, put on one scale per query (`meaning`): every vector is scored anyway, so
/// the distribution comes for free, and only segments that stand out (`LookoutRanking.zGate`) count as meaning
/// matches. That also gives an honest "nothing found". Words rescue what a vector can't hold exactly: codes, IDs and
/// names. Every weight is in `LookoutRanking`.
///
/// Lookout adds to DigUp's search: a path-prefix scope ("Current folder"), the settings filter
/// (`LookoutSearchFilter`) applied before ranking, folder results (`LookoutFolderGrouping`), and per-hit details
/// read in one query each for files and segments instead of two queries a hit. Code search isn't ported.
///
/// The vectors load lazily: with `loadVectors: false` only keyword search is ready, and the first search with a query
/// vector loads them. `releaseVectors()` frees them (20k vectors are about 30 MB), and `reload()` reads them again
/// after the index changed.
///
/// Not thread-safe: one owner uses it from one thread or actor at a time (the app's `LookoutIndexReader`), as
/// `IndexStore` requires.
nonisolated final class Searcher {
    let store: IndexStore
    /// Rows × 768 float16, row-major; nil while released or empty.
    private(set) var matrix: VectorStorage?
    private(set) var rowFile: [Int64] = []
    private(set) var rowSegment: [Int64] = []
    private(set) var rowModality: [Modality] = []
    /// The file kind of each row, for the `kinds` filter on meaning matches.
    private(set) var rowKind: [FileKind] = []
    /// False for the vectors the later pass adds (`Indexer.finishLongFiles`): scored, but they don't set the scale.
    private(set) var rowSetsScale: [Bool] = []
    /// The model the index's vectors were made with (`meta.vector_source`).
    private(set) var vectorSource: String?
    /// False after `releaseVectors()` (or `loadVectors: false`): keyword search still works, and the next search with
    /// a query vector loads them again.
    private(set) var vectorsLoaded = false

    var vectorCount: Int { rowFile.count }

    /// - Parameter loadVectors: False to start with keyword search only; vectors load on the first meaning search.
    /// - Throws: SQLite errors reading the index.
    init(store: IndexStore, loadVectors: Bool = true) throws {
        self.store = store
        if loadVectors { try reload() } else { vectorSource = try store.meta("vector_source") }
    }

    /// Reads all vectors again (after indexing added or removed some).
    ///
    /// - Throws: SQLite errors; the vectors stay released then.
    func reload() throws {
        releaseVectors()
        vectorSource = try store.meta("vector_source")
        var rows = 0
        try store.db.query("SELECT COUNT(*) FROM segments WHERE vec IS NOT NULL") { rows = Int($0.int(0)) }
        guard let matrix = VectorStorage(rows: rows) else {
            vectorsLoaded = true   // nothing to load
            return
        }
        let rowBytes = Vectors.dimension * MemoryLayout<Float16>.stride
        let steps = IndexOptions()
        try store.db.query("""
            SELECT s.id, s.file, s.modality, s.vec, s.kind, s.loc, f.kind, CAST(json_extract(f.info, '$.pages') AS INTEGER)
            FROM segments s JOIN files f ON f.id = s.file WHERE s.vec IS NOT NULL ORDER BY s.id
            """) { row in
            guard let blob = row.blob(3), blob.count == rowBytes, rowFile.count < rows else { return }
            blob.copyBytes(to: UnsafeMutableRawBufferPointer(start: matrix.halves + rowFile.count * Vectors.dimension,
                                                             count: rowBytes))
            rowSegment.append(row.int(0))
            rowFile.append(row.int(1))
            rowModality.append(Modality(rawValue: row.text(2) ?? "") ?? .none)
            rowKind.append(FileKind(rawValue: row.text(6) ?? "") ?? .doc)
            // Past the first step of a long PDF (its pages) or document (its chunks).
            let (kind, place) = (row.text(4), row.isNull(5) ? 0 : Int(row.double(5)))
            let later = row.text(6) == FileKind.pdf.rawValue
                ? kind != SegmentKind.chunk.rawValue && Int(row.int(7)) > steps.bigPDFPages && place > steps.pdfStep
                : kind == SegmentKind.chunk.rawValue && place > steps.docStep
            rowSetsScale.append(!later)
        }
        self.matrix = matrix
        vectorsLoaded = true
    }

    /// Frees the vectors' memory (`VectorStorage` unmaps it); keyword search keeps working.
    func releaseVectors() {
        matrix = nil
        rowFile = []
        rowSegment = []
        rowModality = []
        rowKind = []
        rowSetsScale = []
        vectorsLoaded = false
    }

    /// The most files keyword search keeps, best first, among those the settings filter accepts.
    static let wordFiles = 100
    /// The most keyword-matching segments one search steps through to fill `wordFiles`. Each costs a row and, for a
    /// new file, the filter's `stat`; this bounds a search whose best matches were all deleted since the last sync.
    static let wordWindow = 4_000

    /// Searches the index.
    ///
    /// - Parameters:
    ///   - text: What was typed.
    ///   - queryVector: The query's vector (`Prompts.query`, 768 L2-normalized floats), or nil for keyword search
    ///     only. Loads the vectors first when they're released.
    ///   - scope: A folder to search inside ("Current folder"), as an absolute real path; nil for the whole index.
    ///     Applied to the vector rows and inside the keyword query.
    ///   - kinds: Only files of these kinds; nil for all.
    ///   - filter: Which files the settings allow (`LookoutSearchFilter`); nil shows everything indexed. Its folders
    ///     and types also go into the keyword query, before its limits.
    ///   - limit: The most hits returned, files and folders together.
    ///   - prefixLast: Match the last word as a prefix (it's probably half-typed): the keyword-only first pass.
    /// - Returns: Hits best first, split into strong and weak.
    /// - Throws: SQLite errors.
    func search(_ text: String, queryVector: [Float]?, scope: String? = nil, kinds: Set<FileKind>? = nil,
                filter: LookoutSearchFilter? = nil, limit: Int = 40, prefixLast: Bool = false) throws
        -> LookoutResultSet {
        let zGate = LookoutRanking.zGate
        if queryVector != nil, !vectorsLoaded { try reload() }
        let range = scope.map(Self.prefixRange)
        let scoped = try range.map(files(in:))
        let kindAllowed = { (kind: FileKind?) -> Bool in
            guard let kinds else { return true }
            return kind.map(kinds.contains) ?? false
        }

        // Meaning: score every vector on this query's scale (`meaning`), keep each file's best segment.
        var best: [Int64: (z: Double, cosine: Double, row: Int)] = [:]
        let usedMeaning = queryVector?.count == Vectors.dimension
        if let query = queryVector, usedMeaning, !rowFile.isEmpty {
            let scores = score(query)
            let meaning = Self.meaning(scores, rowModality, setsScale: rowSetsScale)
            for row in 0..<scores.count where kindAllowed(rowKind[row]) && scoped?.contains(rowFile[row]) ?? true {
                let z = meaning[row]
                if z > (best[rowFile[row]]?.z ?? -.infinity) { best[rowFile[row]] = (z, Double(scores[row]), row) }
            }
        }

        // Words: FTS5 with Porter stemming over file names, folder names, OCR, page and document text.
        let terms = Self.terms(text)
        let patterns = Self.patterns(terms, prefixLast: prefixLast)
        var words: [(file: Int64, segment: Int64, snippet: String?)] = []
        var coverage: [Int64: Double] = [:]   // share of the query's words found anywhere in the file
        var allowed: [Int64: Bool] = [:]      // the settings filter's verdict, existence included, asked once a file
        if !patterns.isEmpty {
            // The scope, the kinds and the settings' folders and types go into the query, so its LIMIT is spent on
            // files that may be shown. Rows come best first, and a file counts towards `wordFiles` only once the
            // filter, with its existence check, has accepted it: files deleted since the last sync can't crowd out a
            // valid one further down. `wordWindow` caps the work, and snippets are made only for accepted files.
            let match = SQLValue.text(patterns.joined(separator: " OR "))
            var conditions = "", values = [match]
            if let range {
                conditions += " AND f.path >= ? AND f.path < ?"
                values += [.text(range.lower), .text(range.upper)]
            }
            if let kinds {
                conditions += " AND f.kind IN (\(kinds.map { _ in "?" }.joined(separator: ", ")))"
                values += kinds.map(\.rawValue).sorted().map { .text($0) }
            }
            if let filter {
                let condition = filter.sqlCondition(column: "f.path")
                conditions += " AND " + condition.sql
                values += condition.values
            }
            var seen = Set<Int64>()
            var matched: [(file: Int64, segment: Int64)] = []
            try store.db.scan("""
                SELECT s.file, s.id, f.path FROM fts JOIN segments s ON s.id = fts.rowid JOIN files f ON f.id = s.file
                WHERE fts MATCH ?\(conditions) ORDER BY bm25(fts, 3.0, 1.0) LIMIT \(Self.wordWindow)
                """, values) { row in
                let file = row.int(0)
                if seen.insert(file).inserted {
                    let ok = filter?.allows(row.text(2) ?? "") ?? true
                    allowed[file] = ok
                    if ok { matched.append((file, row.int(1))) }
                }
                return matched.count < Self.wordFiles
            }
            if !matched.isEmpty {
                var snippets: [Int64: String] = [:]
                try store.db.query("""
                    SELECT rowid, snippet(fts, 1, '«', '»', '…', 12), original FROM fts
                    WHERE fts MATCH ? AND rowid IN (\(matched.map { String($0.segment) }.joined(separator: ",")))
                    """, [match]) { row in
                    // Text that normalizing changed is quoted as it's written (with its hamza, harakat, joiners).
                    snippets[row.int(0)] = row.text(2).flatMap { SearchText.snippet($0, terms: terms) } ?? row.text(1)
                }
                words = matched.map { ($0.file, $0.segment, snippets[$0.segment]) }
                let files = words.map { String($0.file) }.joined(separator: ",")
                for pattern in patterns {
                    try store.db.query("""
                        SELECT DISTINCT s.file FROM fts JOIN segments s ON s.id = fts.rowid
                        WHERE fts MATCH ? AND s.file IN (\(files))
                        """, [.text(pattern)]) { coverage[$0.int(0), default: 0] += 1 / Double(patterns.count) }
                }
            }
        }

        // A file qualifies by standing out in meaning, or by containing at least half of the query's words.
        // Score: meaning z + a bonus that grows with word coverage, + 1 for the kind the query asks for.
        // One common word can't beat a strong meaning match; all the words of an exact lookup usually do.
        // (This beat reciprocal-rank fusion on both of DigUp's evals, 2026-10-07: R@1 0.88 vs 0.73 synthetic, 0.86
        // vs 0.82 real.)
        let lookup = Self.isLookup(terms)
        let (meaningWeight, wordsWeight) = lookup
            ? (LookoutRanking.lookupMeaningWeight, LookoutRanking.wordWeight * LookoutRanking.lookupWordFactor)
            : (1, LookoutRanking.wordWeight)
        let hinted = Self.kindHints(text)
        var candidates = Set(best.filter { $0.value.z >= zGate }.keys)
        for (file, share) in coverage where share >= LookoutRanking.wordGate { candidates.insert(file) }
        let fileRows = try files(withIDs: candidates)
        var scored: [Int64: Double] = [:]
        var members: [LookoutFolderGrouping.Member] = []
        for file in candidates {
            guard let row = fileRows[file], allowed[file] ?? filter?.allows(row.path) ?? true else { continue }
            let z = best[file]?.z, share = coverage[file] ?? 0
            var score = meaningWeight * max(z ?? 0, 0) + wordsWeight * pow(share, LookoutRanking.coverageExponent)
            if hinted.contains(row.kind) { score += LookoutRanking.kindHintBonus }
            scored[file] = score
            members.append(.init(path: row.path, score: score, z: z, coverage: share,
                                 match: .init(meaning: (z ?? -.infinity) >= zGate, words: share >= LookoutRanking.wordGate)))
        }

        // Files and folders in one ranked list. Ties go by path, so equal scores keep a stable order.
        enum Entry { case file(Int64), folder(LookoutHit) }
        var entries: [(score: Double, path: String, entry: Entry)] = scored.map { file, score in
            (score: score, path: fileRows[file]!.path, entry: Entry.file(file))
        }
        entries += LookoutFolderGrouping.folders(from: members, excluding: scope).map {
            (score: $0.score, path: $0.path, entry: Entry.folder($0))
        }
        entries.sort { $0.score > $1.score || ($0.score == $1.score && $0.path < $1.path) }
        let page = entries.prefix(limit)

        // Point at the best meaning segment if it stands out; else at the segment the words matched.
        let wordRank = Dictionary(words.enumerated().map { ($0.element.file, (rank: $0.offset + 1, match: $0.element)) },
                                  uniquingKeysWith: { first, _ in first })
        var pointed: [Int64: Int64] = [:]
        for case .file(let file) in page.map(\.entry) {
            let semantic = best[file], keyword = wordRank[file]
            let useMeaning = semantic.map { $0.z >= zGate || keyword == nil } ?? false
            if let id = useMeaning ? semantic.map({ rowSegment[$0.row] }) : keyword?.match.segment { pointed[file] = id }
        }
        let segmentRows = try segments(withIDs: Set(pointed.values).union(pointed.keys.compactMap {
            wordRank[$0]?.match.segment
        }))

        var hits: [LookoutHit] = []
        for item in page {
            switch item.entry {
            case .folder(let folder):
                hits.append(folder)
            case .file(let file):
                guard let row = fileRows[file], let segmentID = pointed[file], let segment = segmentRows[segmentID],
                      let score = scored[file] else { continue }
                let semantic = best[file], keyword = wordRank[file], share = coverage[file] ?? 0
                hits.append(LookoutHit(
                    path: row.path, kind: row.kind, folder: nil, score: score, z: semantic?.z, cosine: semantic?.cosine,
                    coverage: share, keywordRank: keyword?.rank,
                    match: .init(meaning: (semantic?.z ?? -.infinity) >= zGate, words: share >= LookoutRanking.wordGate),
                    segment: segment.kind, segmentID: segmentID, loc: segment.loc, locEnd: segment.locEnd,
                    snippet: Self.snippet(pointedAt: segmentID, segment: segment, keyword: keyword?.match,
                                          matchedKind: keyword.flatMap { segmentRows[$0.match.segment]?.kind }),
                    excerpt: segment.excerpt, modified: row.modified, size: row.size, info: row.info))
            }
        }
        return LookoutResultSet(ranked: hits, terms: terms, isLookup: lookup, usedMeaning: usedMeaning)
    }

    /// How many of `hits` (best first) are strong: scoring at least `ratio` × the top hit. The rest pass the gates but
    /// trail far behind, and the UI folds them under "weaker matches".
    static func strongCount(_ hits: [LookoutHit], ratio: Double = LookoutRanking.strongRatio) -> Int {
        guard let top = hits.first?.score, top > 0 else { return hits.count }
        return hits.prefix { $0.score >= top * ratio }.count
    }

    /// The text of a page, a document's passage or a screenshot's OCR, as it's written: the preview shows the part of
    /// a document that matched.
    ///
    /// - Throws: SQLite errors.
    func text(ofSegment id: Int64) throws -> String? {
        var text: String?
        try store.db.query("SELECT coalesce(original, body) FROM fts WHERE rowid = ?", [.int(id)]) { text = $0.text(0) }
        return text
    }

    // MARK: Details

    /// A `files` row, as a hit needs it.
    struct FileRow {
        let path: String
        let kind: FileKind
        let modified: Double
        let size: Int64
        let info: [String: String]
    }

    /// A `segments` row, as a hit needs it.
    struct SegmentRow {
        let kind: SegmentKind
        let loc: Double?
        let locEnd: Double?
        let excerpt: String?
    }

    /// Quote the matched words only when they come from the segment the hit points at, so a PDF hit on page 5 never
    /// shows page 2's words. A segment with no place and no text of its own (a screenshot's image vector) can borrow
    /// them from its file's OCR text, which describes the same picture; never from the name row.
    private static func snippet(pointedAt segmentID: Int64, segment: SegmentRow,
                                keyword: (file: Int64, segment: Int64, snippet: String?)?,
                                matchedKind: SegmentKind?) -> String? {
        let marked = { (text: String?) in text.flatMap { $0.contains("«") ? Excerpt.line($0, limit: 400) : nil } }
        if let keyword, keyword.segment == segmentID, let own = marked(keyword.snippet) { return own }
        guard segment.excerpt == nil, segment.loc == nil, let keyword, matchedKind != SegmentKind.name else { return nil }
        return marked(keyword.snippet)
    }

    /// The ids of the files under `range` (a scope), from the UNIQUE path index.
    func files(in range: (lower: String, upper: String)) throws -> Set<Int64> {
        var ids = Set<Int64>()
        try store.db.query("SELECT id FROM files WHERE path >= ? AND path < ?", [.text(range.lower), .text(range.upper)]) {
            ids.insert($0.int(0))
        }
        return ids
    }

    /// The rows of `ids`, in one query. Ids gone from the index since the vectors loaded are simply missing.
    func files(withIDs ids: Set<Int64>) throws -> [Int64: FileRow] {
        guard !ids.isEmpty else { return [:] }
        var rows: [Int64: FileRow] = [:]
        try store.db.query("""
            SELECT id, path, kind, mtime, size, info FROM files WHERE id IN (\(ids.map(String.init).joined(separator: ",")))
            """) { row in
            var info: [String: String] = [:]
            if let json = row.text(5)?.data(using: .utf8) {
                info = (try? JSONSerialization.jsonObject(with: json) as? [String: String]) ?? [:]
            }
            rows[row.int(0)] = FileRow(path: row.text(1) ?? "", kind: FileKind(rawValue: row.text(2) ?? "") ?? .doc,
                                       modified: row.double(3), size: row.int(4), info: info)
        }
        return rows
    }

    /// The rows of `ids`, in one query.
    func segments(withIDs ids: Set<Int64>) throws -> [Int64: SegmentRow] {
        guard !ids.isEmpty else { return [:] }
        var rows: [Int64: SegmentRow] = [:]
        try store.db.query("""
            SELECT id, kind, loc, loc_end, excerpt FROM segments
            WHERE id IN (\(ids.map(String.init).joined(separator: ",")))
            """) { row in
            rows[row.int(0)] = SegmentRow(kind: SegmentKind(rawValue: row.text(1) ?? "") ?? .name,
                                          loc: row.isNull(2) ? nil : row.double(2),
                                          locEnd: row.isNull(3) ? nil : row.double(3), excerpt: row.text(4))
        }
        return rows
    }

    /// Every path that starts with `folder/`, as a range on the path index (as `IndexStore.scope` does).
    static func prefixRange(_ folder: String) -> (lower: String, upper: String) {
        let prefix = folder.hasSuffix("/") ? folder : folder + "/"
        return (prefix, prefix + "\u{10FFFF}")
    }
}
