import Foundation

/// Searching with a vector alone: a picture someone dropped or pasted, or a file already in the index (Find Similar).
///
/// There are no words, so a file qualifies by meaning alone: its best segment must stand out on this query's own
/// scale (`Searcher.meaning`, `LookoutRanking.zGate`), and it scores that z. Pictures and documents sit on separate
/// scales even after `meaning` centers each modality (a picture query's cosines to other pictures run far above its
/// cosines to text), so they're ranked, grouped into folders, and split into strong and weak each on their own
/// (`LookoutSimilarResults`). The file searched with never appears in its own results.
nonisolated extension Searcher {
    /// Searches the index with `vector`.
    ///
    /// - Parameters:
    ///   - vector: 768 L2-normalized floats: a picture's image vector, or a stored vector. Loads the vectors first when
    ///     they're released.
    ///   - queryIsPicture: The vector is a picture's (it puts the pictures group first).
    ///   - excluding: Paths, as the index stores them, never to return: the file searched with.
    ///   - scope: A folder to search inside, as an absolute real path; nil for the whole index.
    ///   - kinds: Only files of these kinds; nil for all.
    ///   - filter: Which files the settings allow; nil shows everything indexed.
    ///   - limit: The most hits in each group, files and folders together.
    /// - Returns: Both groups in display order, each split into strong and weak.
    /// - Throws: SQLite errors.
    func similar(to vector: [Float], queryIsPicture: Bool, excluding: Set<String> = [], scope: String? = nil,
                 kinds: Set<FileKind>? = nil, filter: LookoutSearchFilter? = nil, limit: Int = 40) throws
        -> LookoutSimilarResults {
        guard vector.count == Vectors.dimension else { return LookoutSimilarResults(queryIsPicture: queryIsPicture) }
        if !vectorsLoaded { try reload() }
        let scoped = try scope.map(Self.prefixRange).map(files(in:))
        let excludedIDs = try fileIDs(forPaths: excluding)

        // Each file's best segment on this query's scale, as text search scores meaning.
        var best: [Int64: (z: Double, cosine: Double, row: Int)] = [:]
        if !rowFile.isEmpty {
            let scores = score(vector)
            let meaning = Self.meaning(scores, rowModality, setsScale: rowSetsScale)
            for row in scores.indices {
                let file = rowFile[row]
                guard !excludedIDs.contains(file), kinds?.contains(rowKind[row]) ?? true,
                      scoped?.contains(file) ?? true else { continue }
                if meaning[row] > (best[file]?.z ?? -.infinity) { best[file] = (meaning[row], Double(scores[row]), row) }
            }
        }

        let candidates = Set(best.filter { $0.value.z >= LookoutRanking.zGate }.keys)
        let fileRows = try files(withIDs: candidates)
        typealias GroupKind = LookoutSimilarResults.GroupKind
        var filesByGroup: [GroupKind: [Int64]] = [:]
        var members: [GroupKind: [LookoutFolderGrouping.Member]] = [:]
        for file in candidates {
            guard let row = fileRows[file], let match = best[file], filter?.allows(row.path) ?? true else { continue }
            let group = GroupKind(row.kind)
            filesByGroup[group, default: []].append(file)
            members[group, default: []].append(.init(path: row.path, score: match.z, z: match.z, coverage: 0,
                                                     match: .meaning))
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

        enum Entry { case file(Int64), folder(LookoutHit) }
        var pages: [GroupKind: [Entry]] = [:]
        var pointed: Set<Int64> = []
        for group in GroupKind.allCases {
            var entries: [(score: Double, path: String, entry: Entry)] = (filesByGroup[group] ?? []).map { file in
                (best[file]!.z, fileRows[file]!.path, .file(file))
            }
            entries += (folders[group] ?? []).map { ($0.score, $0.path, .folder($0)) }
            entries.sort { $0.score > $1.score || ($0.score == $1.score && $0.path < $1.path) }
            let page = entries.prefix(limit).map(\.entry)
            for case .file(let file) in page { pointed.insert(rowSegment[best[file]!.row]) }
            pages[group] = page
        }
        let segmentRows = try segments(withIDs: pointed)

        let groups = LookoutSimilarResults.order(queryIsPicture: queryIsPicture).map { group in
            let hits: [LookoutHit] = (pages[group] ?? []).compactMap { entry in
                switch entry {
                case .folder(let folder):
                    return folder
                case .file(let file):
                    guard let row = fileRows[file], let match = best[file] else { return nil }
                    let segmentID = rowSegment[match.row]
                    guard let segment = segmentRows[segmentID] else { return nil }
                    return LookoutHit(
                        path: row.path, kind: row.kind, folder: nil, score: match.z, z: match.z, cosine: match.cosine,
                        coverage: 0, keywordRank: nil, match: .meaning, segment: segment.kind, segmentID: segmentID,
                        loc: segment.loc, locEnd: segment.locEnd, snippet: nil, excerpt: segment.excerpt,
                        modified: row.modified, size: row.size, info: row.info)
                }
            }
            return LookoutSimilarResults.Group(kind: group, ranked: hits)
        }
        return LookoutSimilarResults(queryIsPicture: queryIsPicture, groups: groups)
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
