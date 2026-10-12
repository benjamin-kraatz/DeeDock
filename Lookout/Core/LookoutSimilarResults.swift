/// The results of a search with a picture or with a file's stored vector (`Searcher.similar`): no words, so no names,
/// and two groups ranked on their own, because Lookout scores pictures and documents on separate scales.
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

    /// No results yet, with both groups empty in their order.
    init(queryIsPicture: Bool) {
        self.queryIsPicture = queryIsPicture
        groups = Self.order(queryIsPicture: queryIsPicture).map { Group(kind: $0) }
    }

    init(queryIsPicture: Bool, groups: [Group]) {
        self.queryIsPicture = queryIsPicture
        self.groups = groups
    }

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
