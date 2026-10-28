/// The results of a search with a picture or with a file's stored vector (`Searcher.similar`), alone or with words typed
/// beside it: no names, and two groups ranked on their own, because Lookout scores pictures and documents on separate
/// scales.
///
/// The group the query belongs to comes first: for a picture, the pictures that look like it, then the documents
/// about what it shows; for a document, the documents that say something similar, then the pictures of it. Each group
/// splits at its own `LookoutRanking.strongRatio` of its own top score.
nonisolated struct LookoutSimilarResults: Sendable, Equatable {
    /// Which files a group holds.
    enum GroupKind: String, Sendable, Equatable, CaseIterable {
        /// Pictures and screenshots.
        case pictures
        /// PDFs and documents.
        case documents

        /// The group a file of `kind` belongs to.
        init(_ kind: FileKind) {
            switch kind {
            case .image, .screenshot: self = .pictures
            case .pdf, .doc: self = .documents
            }
        }
    }

    /// One group's hits, best first.
    struct Group: Sendable, Equatable, Identifiable {
        let kind: GroupKind
        /// Hits scoring at least `strongRatio` × the group's top score.
        var strong: [LookoutHit] = []
        /// The rest that passed the meaning gate.
        var weak: [LookoutHit] = []

        var id: GroupKind { kind }
        var all: [LookoutHit] { strong + weak }
        var count: Int { strong.count + weak.count }
        var isEmpty: Bool { strong.isEmpty && weak.isEmpty }

        init(kind: GroupKind, strong: [LookoutHit] = [], weak: [LookoutHit] = []) {
            self.kind = kind
            self.strong = strong
            self.weak = weak
        }

        /// Splits `ranked` (best first) at `strongRatio` of its top score.
        init(kind: GroupKind, ranked: [LookoutHit]) {
            let strongCount = Searcher.strongCount(ranked)
            self.init(kind: kind, strong: Array(ranked.prefix(strongCount)), weak: Array(ranked.dropFirst(strongCount)))
        }
    }

    /// Whether the query was a picture (an image vector: a dropped or pasted picture, a photo, a screenshot, a
    /// scanned page) rather than a document's text. It decides the group order and the "why it matched" wording.
    var queryIsPicture: Bool
    /// Both groups, in display order (`order(queryIsPicture:)`).
    var groups: [Group]
    /// The words typed beside the picture that these results were ranked with, trimmed; empty for none. "Why it
    /// matched" names them.
    var words: String
    /// Their keyword terms (`Searcher.terms`, without `Searcher.pictureConnectors`), for highlighting in snippets.
    var terms: [String]
    /// The words are a lookup (codes or long numbers), so exact words counted double.
    var isLookup: Bool

    /// No results yet, with both groups empty in their order.
    init(queryIsPicture: Bool, words: String = "") {
        self.init(queryIsPicture: queryIsPicture, groups: Self.order(queryIsPicture: queryIsPicture).map { Group(kind: $0) },
                  words: words)
    }

    init(queryIsPicture: Bool, groups: [Group], words: String = "", terms: [String] = [], isLookup: Bool = false) {
        self.queryIsPicture = queryIsPicture
        self.groups = groups
        self.words = words
        self.terms = terms
        self.isLookup = isLookup
    }

    /// Words were typed beside the picture.
    var hasWords: Bool { !words.isEmpty }

    /// The group order: the query's own kind first.
    static func order(queryIsPicture: Bool) -> [GroupKind] {
        queryIsPicture ? [.pictures, .documents] : [.documents, .pictures]
    }

    /// Nothing stands out in either group: the honest empty state.
    var hasNoStrongHits: Bool { groups.allSatisfy(\.strong.isEmpty) }
    /// Every hit of both groups, strong then weak within each, in group order.
    var all: [LookoutHit] { groups.flatMap(\.all) }
    var count: Int { groups.reduce(0) { $0 + $1.count } }

    /// The group holding `path`, if any.
    func group(containing path: String) -> Group? {
        groups.first { group in group.all.contains { $0.path == path } }
    }
}

/// Words typed beside a picture (or a file Find Similar searches with), as `Searcher.similar` takes them.
nonisolated struct LookoutSimilarWords: Sendable, Equatable {
    /// What was typed, trimmed.
    var text: String
    /// Its query vector (`Prompts.query`), or nil when the encoder couldn't make one: the words then count as
    /// keywords only.
    var vector: [Float]?
    /// How much the words count against the picture, 0…1 (`LookoutRanking.pictureWordsWeight`).
    var weight: Double = LookoutRanking.pictureWordsWeight
}

/// What a file already in the index searches with (Find Similar): one of its stored vectors and what kind of vector
/// it is. Nothing is encoded, so the search is instant.
nonisolated struct LookoutSimilarSource: Sendable, Equatable {
    /// 768 L2-normalized floats, as stored (float16, widened).
    let vector: [Float]
    /// `.image` for a picture, a screenshot's image or a rendered page; `.text` for a passage or a page's text.
    let modality: Modality
    let segment: SegmentKind
    /// The PDF page the vector belongs to, for "From your index · Page 7".
    let page: Int?
    /// The file's own path in the index, which its results leave out.
    let path: String
}
