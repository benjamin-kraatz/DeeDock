import Foundation
@testable import DeeDock

/// Lookout hits and result sets for the search UI's tests.
enum LookoutUIFixtures {
    static func hit(_ path: String, kind: FileKind? = .doc, match: LookoutHit.Match = .meaning,
                    segment: SegmentKind? = .chunk, loc: Double? = nil, snippet: String? = nil,
                    excerpt: String? = nil, folderFiles: Int? = nil) -> LookoutHit {
        LookoutHit(path: path, kind: folderFiles == nil ? kind : nil,
                   folder: folderFiles.map { .init(matchingFiles: $0, topFiles: []) },
                   score: 1, z: nil, cosine: nil, coverage: 0, keywordRank: nil, match: match,
                   segment: folderFiles == nil ? segment : nil, segmentID: nil, loc: loc, locEnd: loc,
                   snippet: snippet, excerpt: excerpt, modified: 1_786_874_400, size: 1_000, info: [:])
    }

    static func results(strong: [LookoutHit], weak: [LookoutHit] = [], isLookup: Bool = false) -> LookoutResultSet {
        var set = LookoutResultSet()
        set.strong = strong
        set.weak = weak
        set.isLookup = isLookup
        set.usedMeaning = true
        return set
    }
}
