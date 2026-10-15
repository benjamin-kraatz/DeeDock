import Foundation

/// Folder results, a DOKK addition to DigUp's search: a folder whose direct-child files keep matching is often what
/// someone is looking for ("the tax documents"), so it joins the ranked list beside its files.
///
/// A folder qualifies when at least `LookoutRanking.folderMinimumFiles` of its direct children qualify (deeper files
/// count for their own folder only). Its score is the average of its best `folderMinimumFiles` file scores, plus
/// `folderBonusPerFile` for each matching file beyond them, the bonus capped at `folderBonusCap`. The files stay in
/// the list too.
nonisolated enum LookoutFolderGrouping {
    /// A qualifying file, as far as grouping needs it.
    struct Member: Sendable {
        let path: String
        let score: Double
        let z: Double?
        let coverage: Double
        let match: LookoutHit.Match
    }

    /// The folders `members` make, unordered.
    ///
    /// - Parameters:
    ///   - members: Every qualifying file (not only the ones that make the page), already filtered.
    ///   - excluding: A folder never to return: the scope being searched ("Current folder" must not offer itself).
    static func folders(from members: [Member], excluding: String? = nil) -> [LookoutHit] {
        let excluded = excluding.map(Self.trimmed)
        var byFolder: [String: [Member]] = [:]
        for member in members {
            byFolder[(member.path as NSString).deletingLastPathComponent, default: []].append(member)
        }
        return byFolder.compactMap { folder, files -> LookoutHit? in
            guard files.count >= LookoutRanking.folderMinimumFiles, folder != excluded, !folder.isEmpty else {
                return nil
            }
            let best = files.sorted { $0.score > $1.score || ($0.score == $1.score && $0.path < $1.path) }
            let top = Array(best.prefix(LookoutRanking.folderMinimumFiles))
            let meaning = files.contains { $0.match != .words }
            let words = files.contains { $0.match != .meaning }
            return LookoutHit(
                path: folder, kind: nil,
                folder: .init(matchingFiles: files.count, topFiles: top.map(\.path)),
                score: score(fileScores: files.map(\.score)),
                z: best.first?.z, cosine: nil, coverage: best.first?.coverage ?? 0, keywordRank: nil,
                match: .init(meaning: meaning, words: words),
                segment: nil, segmentID: nil, loc: nil, locEnd: nil, snippet: nil, excerpt: nil,
                modified: nil, size: nil, info: [:])
        }
    }

    /// A folder's score from its matching files' scores (any order). Meaningful for `folderMinimumFiles` or more.
    static func score(fileScores: [Double]) -> Double {
        let sorted = fileScores.sorted(by: >)
        let top = sorted.prefix(LookoutRanking.folderMinimumFiles)
        let average = top.reduce(0, +) / Double(max(top.count, 1))
        let extra = Double(max(sorted.count - LookoutRanking.folderMinimumFiles, 0))
        return average + min(extra * LookoutRanking.folderBonusPerFile, LookoutRanking.folderBonusCap)
    }

    private static func trimmed(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
