import Foundation

/// One Lookout result: a file whose contents match the query, or a folder holding several such files
/// (`LookoutFolderGrouping`). Everything the result row and the preview's "why it matched" need is here, so the UI
/// never queries the index itself.
nonisolated struct LookoutHit: Sendable, Equatable, Identifiable {
    /// Why a hit qualified, for the preview's explanation.
    enum Match: String, Sendable, Equatable {
        /// Its best segment stands out in meaning (`LookoutRanking.zGate`), with too few of the words to qualify by
        /// them.
        case meaning
        /// It has at least `LookoutRanking.wordGate` of the query's words, and nothing stands out in meaning.
        case words
        /// Both of the above.
        case both

        init(meaning: Bool, words: Bool) {
            self = meaning && words ? .both : meaning ? .meaning : .words
        }
    }

    /// What makes a folder a result.
    struct Folder: Sendable, Equatable {
        /// How many of its direct-child files qualify (at least `LookoutRanking.folderMinimumFiles`).
        let matchingFiles: Int
        /// Its best files' paths, best first (the ones its score averages).
        let topFiles: [String]
    }

    /// Absolute path, as the index stores it (real paths: `/private/var`, not `/var`).
    let path: String
    /// The file's kind; nil for a folder.
    let kind: FileKind?
    /// Set for a folder result, nil for a file.
    let folder: Folder?
    /// The rank score, for ordering only: meaning z plus the word bonus plus the kind hint (`Searcher`), or the
    /// folder formula. It isn't comparable across queries.
    let score: Double
    /// How far the best segment stands out for this query, in standard deviations (`Searcher.meaning`). Nil when the
    /// search had no query vector or the file has no vectors. A folder carries its best file's.
    let z: Double?
    /// The raw cosine similarity of that segment.
    let cosine: Double?
    /// The share of the query's words found anywhere in the file, 0…1. A folder carries its best file's.
    let coverage: Double
    /// 1-based rank among keyword matches, when the words matched.
    let keywordRank: Int?
    let match: Match
    /// The segment the hit points at: the best meaning segment when it stands out, else the one the words matched.
    /// Nil for a folder.
    let segment: SegmentKind?
    let segmentID: Int64?
    /// A PDF page number (1-based) for `page` and `pageImage` segments, a chunk number for `chunk`.
    let loc: Double?
    let locEnd: Double?
    /// The query's words in context, marked « » as SQLite's `snippet()` marks them, from the segment the hit points
    /// at (or, for a picture with no text of its own, its OCR text). Nil when the words didn't match there.
    let snippet: String?
    /// The text the index stored for the segment (a passage's or a screenshot's first line), unmarked.
    let excerpt: String?
    /// Modification date (seconds since 1970) and size as of the last sync. Nil for a folder.
    let modified: Double?
    let size: Int64?
    /// What indexing learned: `width`, `height`, `pages`, `taken`… (`Indexer`).
    let info: [String: String]

    var id: String { path }
    var isFolder: Bool { folder != nil }
    var url: URL { URL(fileURLWithPath: path, isDirectory: isFolder) }

    /// The PDF page the hit points at, for "Page 7". Nil for anything but a page.
    var page: Int? {
        guard let loc, segment == .page || segment == .pageImage else { return nil }
        return Int(loc)
    }

    /// What a row shows under the name: the marked words when they matched here, else the stored excerpt.
    var displayText: String? { snippet ?? excerpt }
}
