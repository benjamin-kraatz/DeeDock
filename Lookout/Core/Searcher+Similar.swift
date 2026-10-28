import Foundation

/// Searching with a vector: a picture someone dropped or pasted, or a file already in the index (Find Similar), alone
/// or with words typed beside it.
///
/// Without words, a file qualifies by meaning alone: its best segment must stand out on this query's own scale
/// (`Searcher.meaning`, `LookoutRanking.zGate`), and it scores that z. Pictures and documents sit on separate scales
/// even after `meaning` centers each modality (a picture query's cosines to other pictures run far above its cosines to
/// text), so they're ranked, grouped into folders, and split into strong and weak each on their own
/// (`LookoutSimilarResults`). The file searched with never appears in its own results.
///
/// Words typed beside the picture ("this, but at night") change both parts (DEE-126). Meaning becomes the blend of
/// the picture's and the words' scores (`Searcher.blend`), and the words count as keywords as they do in a search by
/// words: a file qualifies by the blend or by having half the words, and scores
/// `max(z, 0) + 2 × coverage^1.5`, with lookups and kind words weighed as `search` weighs them.
nonisolated extension Searcher {
    /// Words connecting a picture to what's typed beside it ("but at night", "like this, in red"). The vector still
    /// reads them; keyword coverage doesn't count them, so "but black" covers a file with "black" fully.
    static let pictureConnectors: Set<String> = ["but", "like", "same", "similar", "instead", "version", "just", "only"]

    /// Searches the index with `vector`, and with `words` when someone typed them beside it.
    ///
    /// - Parameters:
    ///   - vector: 768 L2-normalized floats: a picture's image vector, or a stored vector. Loads the vectors first when
    ///     they're released.
    ///   - queryIsPicture: The vector is a picture's (it puts the pictures group first).
    ///   - words: Words typed beside it, with their vector and weight; nil or empty text for the vector alone. Without
    ///     a vector (the encoder failed) they count as keywords only.
    ///   - excluding: Paths, as the index stores them, never to return: the file searched with.
    ///   - scope: A folder to search inside, as an absolute real path; nil for the whole index.
    ///   - kinds: Only files of these kinds; nil for all.
    ///   - filter: Which files the settings allow; nil shows everything indexed.
    ///   - limit: The most hits in each group, files and folders together.
    /// - Returns: Both groups in display order, each split into strong and weak.
    /// - Throws: SQLite errors.
    func similar(to vector: [Float], queryIsPicture: Bool, words: LookoutSimilarWords? = nil,
                 excluding: Set<String> = [], scope: String? = nil, kinds: Set<FileKind>? = nil,
                 filter: LookoutSearchFilter? = nil, limit: Int = 40) throws -> LookoutSimilarResults {
        let words = words.flatMap { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        guard vector.count == Vectors.dimension else {
            return LookoutSimilarResults(queryIsPicture: queryIsPicture, words: words?.text ?? "")
        }
        if !vectorsLoaded { try reload() }
        let zGate = LookoutRanking.zGate
        let range = scope.map(Self.prefixRange)
        let scoped = try range.map(files(in:))
        let excludedIDs = try fileIDs(forPaths: excluding)

        // Each file's best segment on this query's scale, as text search scores meaning. With words, the picture's
        // and the words' scales blended.
        var best: [Int64: (z: Double, cosine: Double, row: Int)] = [:]
        if !rowFile.isEmpty {
            let scores = score(vector)
            var meaning = Self.meaning(scores, rowModality, setsScale: rowSetsScale)
            if let words, let wordsVector = words.vector, wordsVector.count == Vectors.dimension {
                let wordsMeaning = Self.meaning(score(wordsVector), rowModality, setsScale: rowSetsScale)
                meaning = Self.blend(meaning, wordsMeaning, weight: words.weight, setsScale: rowSetsScale)
            }
            for row in scores.indices {
                let file = rowFile[row]
                guard !excludedIDs.contains(file), kinds?.contains(rowKind[row]) ?? true,
                      scoped?.contains(file) ?? true else { continue }
                if meaning[row] > (best[file]?.z ?? -.infinity) { best[file] = (meaning[row], Double(scores[row]), row) }
            }
        }

        // The typed words as keywords, as in a search by words, without the words that only tie them to the picture.
        let text = words?.text ?? ""
        let terms = Self.terms(text).filter { !Self.pictureConnectors.contains($0) }
        var found = try wordMatches(Self.patterns(terms, prefixLast: false), terms: terms, range: range, kinds: kinds,
                                    filter: filter)
        found.matches.removeAll { excludedIDs.contains($0.file) }
        let lookup = Self.isLookup(terms)
        let (meaningWeight, wordsWeight) = lookup
            ? (LookoutRanking.lookupMeaningWeight, LookoutRanking.wordWeight * LookoutRanking.lookupWordFactor)
            : (1, LookoutRanking.wordWeight)
        let hinted = Self.kindHints(text)

        var candidates = Set(best.filter { $0.value.z >= zGate }.keys)
        for (file, share) in found.coverage where share >= LookoutRanking.wordGate && !excludedIDs.contains(file) {
            candidates.insert(file)
        }
        let fileRows = try files(withIDs: candidates)
        typealias GroupKind = LookoutSimilarResults.GroupKind
        var scored: [Int64: Double] = [:]
        var filesByGroup: [GroupKind: [Int64]] = [:]
        var members: [GroupKind: [LookoutFolderGrouping.Member]] = [:]
        for file in candidates {
            guard let row = fileRows[file], found.allowed[file] ?? filter?.allows(row.path) ?? true else { continue }
            let z = best[file]?.z, share = found.coverage[file] ?? 0
            var score: Double
            if words == nil {
                score = z ?? 0
            } else {
                score = meaningWeight * max(z ?? 0, 0) + wordsWeight * pow(share, LookoutRanking.coverageExponent)
                if hinted.contains(row.kind) { score += LookoutRanking.kindHintBonus }
            }
            scored[file] = score
            let group = GroupKind(row.kind)
            filesByGroup[group, default: []].append(file)
            members[group, default: []].append(.init(
                path: row.path, score: score, z: z, coverage: share,
                match: .init(meaning: (z ?? -.infinity) >= zGate, words: share >= LookoutRanking.wordGate)))
        }

        // Folders form within a group. One that forms in both stays where it scores higher, so a path is listed once.
        var folders: [GroupKind: [LookoutHit]] = [:]
        for group in GroupKind.allCases {
            folders[group] = LookoutFolderGrouping.folders(from: members[group] ?? [], excluding: scope)
        }
        let pictureFolders = Dictionary((folders[.pictures] ?? []).map { ($0.path, $0.score) }, uniquingKeysWith: max)
        let documentFolders = Dictionary((folders[.documents] ?? []).map { ($0.path, $0.score) }, uniquingKeysWith: max)
        folders[.pictures] = folders[.pictures]?.filter { $0.score >= documentFolders[$0.path] ?? -.infinity }
        folders[.documents] = folders[.documents]?.filter { $0.score > pictureFolders[$0.path] ?? -.infinity }

        // Point at the best meaning segment if it stands out; else at the segment the words matched.
        let wordRank = Dictionary(found.matches.enumerated().map { ($0.element.file, (rank: $0.offset + 1,
                                                                                      match: $0.element)) },
                                  uniquingKeysWith: { first, _ in first })
        enum Entry { case file(Int64), folder(LookoutHit) }
        var pages: [GroupKind: [Entry]] = [:]
        var pointed: [Int64: Int64] = [:]
        for group in GroupKind.allCases {
            var entries: [(score: Double, path: String, entry: Entry)] = (filesByGroup[group] ?? []).map { file in
                (scored[file]!, fileRows[file]!.path, .file(file))
            }
            entries += (folders[group] ?? []).map { ($0.score, $0.path, .folder($0)) }
            entries.sort { $0.score > $1.score || ($0.score == $1.score && $0.path < $1.path) }
            let page = entries.prefix(limit).map(\.entry)
            for case .file(let file) in page {
                let semantic = best[file], keyword = wordRank[file]
                let useMeaning = semantic.map { $0.z >= zGate || keyword == nil } ?? false
                if let id = useMeaning ? semantic.map({ rowSegment[$0.row] }) : keyword?.match.segment {
                    pointed[file] = id
                }
            }
            pages[group] = page
        }
        let segmentRows = try segments(withIDs: Set(pointed.values).union(pointed.keys.compactMap {
            wordRank[$0]?.match.segment
        }))

        let groups = LookoutSimilarResults.order(queryIsPicture: queryIsPicture).map { group in
            let hits: [LookoutHit] = (pages[group] ?? []).compactMap { entry in
                switch entry {
                case .folder(let folder):
                    return folder
                case .file(let file):
                    guard let row = fileRows[file], let segmentID = pointed[file], let segment = segmentRows[segmentID],
                          let score = scored[file] else { return nil }
                    let semantic = best[file], keyword = wordRank[file], share = found.coverage[file] ?? 0
                    return LookoutHit(
                        path: row.path, kind: row.kind, folder: nil, score: score, z: semantic?.z,
                        cosine: semantic?.cosine, coverage: share, keywordRank: keyword?.rank,
                        match: .init(meaning: (semantic?.z ?? -.infinity) >= zGate,
                                     words: share >= LookoutRanking.wordGate),
                        segment: segment.kind, segmentID: segmentID, loc: segment.loc, locEnd: segment.locEnd,
                        snippet: Self.snippet(pointedAt: segmentID, segment: segment, keyword: keyword?.match,
                                              matchedKind: keyword.flatMap { segmentRows[$0.match.segment]?.kind }),
                        excerpt: segment.excerpt, modified: row.modified, size: row.size, info: row.info)
                }
            }
            return LookoutSimilarResults.Group(kind: group, ranked: hits)
        }
        return LookoutSimilarResults(queryIsPicture: queryIsPicture, groups: groups, words: words?.text ?? "",
                                     terms: terms, isLookup: lookup)
    }

    /// The stored vector a file already in the index searches with (Find Similar): the segment `preferredSegment`
    /// when it's the file's and has a vector (a Lookout hit's matched segment, such as that PDF page), else the
    /// file's picture, else its first segment with a vector.
    ///
    /// - Parameter path: The file, as the index stores it (a real path).
    /// - Returns: Nil when the file isn't in the index or has no vector yet.
    /// - Throws: SQLite errors.
    func similarSource(path: String, preferredSegment: Int64? = nil) throws -> LookoutSimilarSource? {
        var source: LookoutSimilarSource?
        let rowBytes = Vectors.dimension * MemoryLayout<Float16>.stride
        try store.db.query("""
            SELECT s.kind, s.modality, s.loc, s.vec FROM segments s JOIN files f ON f.id = s.file
            WHERE f.path = ? AND s.vec IS NOT NULL
            ORDER BY s.id = ? DESC, s.kind = 'image' DESC, s.id LIMIT 1
            """, [.text(path), .int(preferredSegment ?? -1)]) { row in
            guard let blob = row.blob(3), blob.count == rowBytes else { return }
            let vector = blob.withUnsafeBytes { raw in raw.bindMemory(to: Float16.self).map(Float.init) }
            let kind = SegmentKind(rawValue: row.text(0) ?? "") ?? .chunk
            let loc = row.isNull(2) ? nil : Int(row.double(2))
            source = LookoutSimilarSource(vector: vector, modality: Modality(rawValue: row.text(1) ?? "") ?? .text,
                                          segment: kind, page: kind == .page || kind == .pageImage ? loc : nil,
                                          path: path)
        }
        return source
    }

    /// Which of `paths` (as the index stores them) the index holds with at least one vector.
    ///
    /// - Throws: SQLite errors.
    func indexedPaths(_ paths: Set<String>) throws -> Set<String> {
        guard !paths.isEmpty else { return [] }
        var found = Set<String>()
        let marks = paths.map { _ in "?" }.joined(separator: ",")
        try store.db.query("""
            SELECT f.path FROM files f WHERE f.path IN (\(marks))
            AND EXISTS (SELECT 1 FROM segments s WHERE s.file = f.id AND s.vec IS NOT NULL)
            """, paths.sorted().map { .text($0) }) { row in
            if let path = row.text(0) { found.insert(path) }
        }
        return found
    }

    /// The ids of `paths` in the index; paths it doesn't hold are left out.
    private func fileIDs(forPaths paths: Set<String>) throws -> Set<Int64> {
        guard !paths.isEmpty else { return [] }
        var ids = Set<Int64>()
        let marks = paths.map { _ in "?" }.joined(separator: ",")
        try store.db.query("SELECT id FROM files WHERE path IN (\(marks))", paths.sorted().map { .text($0) }) {
            ids.insert($0.int(0))
        }
        return ids
    }
}
