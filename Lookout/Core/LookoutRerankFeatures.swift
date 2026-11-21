import Foundation

/// What a reranker knows about one hit, as numbers: what the search measured for it, where it stands among the
/// query's other hits, and what the query asks for (DEE-166). Everything here is known at search time, so the app's
/// click log (`LookoutClickLog`) records the same rows `LookoutBench rerank` trains on.
///
/// Change `version` with any change to the features or their order: logged rows of another version don't mix.
nonisolated enum LookoutRerankFeatures {
    static let version = 1

    static let names = [
        "score", "rank", "scoreRatio", "z", "zGap", "cosine", "coverage", "keywordRank", "meaningMatch", "wordsMatch",
        "isFolder", "kindScreenshot", "kindImage", "kindPDF", "kindDoc", "segmentName", "segmentPage", "segmentChunk",
        "segmentOCR", "segmentImage", "kindHint", "queryHasKind", "dateHit", "queryHasDate", "nameShare",
        "hasSnippet", "page", "ageDays", "sizeLog", "queryTerms", "isLookup",
    ]

    /// One row per hit, in `names` order.
    static func rows(query: String, hits: [LookoutHit], isLookup: Bool, now: Date) -> [[Double]] {
        let terms = Searcher.terms(query)
        let hinted = Searcher.kindHints(query)
        let date = DateHint.parse(query, now: now)
        let topScore = hits.first?.score ?? 0
        let topZ = hits.compactMap(\.z).max() ?? 0
        return hits.enumerated().map { index, hit in
            let name = (hit.path as NSString).lastPathComponent.lowercased()
            let nameShare = terms.isEmpty ? 0 : Double(terms.filter { name.contains($0) }.count) / Double(terms.count)
            let fileDate = hit.modified.map { DateHint.fileDate(modified: $0, info: hit.info) }
            let flag = { (test: Bool) in test ? 1.0 : 0.0 }
            return [
                hit.score, Double(index + 1), topScore > 0 ? hit.score / topScore : 0, hit.z ?? -3,
                topZ - (hit.z ?? -3), hit.cosine ?? 0, hit.coverage, hit.keywordRank.map { 1 / Double($0) } ?? 0,
                flag(hit.match != .words), flag(hit.match != .meaning), flag(hit.isFolder),
                flag(hit.kind == .screenshot), flag(hit.kind == .image), flag(hit.kind == .pdf), flag(hit.kind == .doc),
                flag(hit.segment == .name), flag(hit.segment == .page || hit.segment == .pageImage),
                flag(hit.segment == .chunk), flag(hit.segment == .ocr), flag(hit.segment == .image),
                flag(hit.kind.map(hinted.contains) ?? false), flag(!hinted.isEmpty),
                flag(date.flatMap { hint in fileDate.map(hint.interval.contains) } ?? false), flag(date != nil),
                nameShare, flag(hit.snippet != nil), hit.loc ?? 0,
                fileDate.map { max(now.timeIntervalSince($0), 0) / 86_400 } ?? -1,
                hit.size.map { log10(Double(max($0, 1))) } ?? 0, Double(terms.count), flag(isLookup),
            ]
        }
    }
}
