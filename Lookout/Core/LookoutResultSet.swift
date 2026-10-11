/// One Lookout search's results in rank order, split into the strong ones and the weaker ones the UI folds away
/// (`LookoutRanking.strongRatio`).
nonisolated struct LookoutResultSet: Sendable, Equatable {
    /// Hits scoring at least `strongRatio` × the top score, best first.
    var strong: [LookoutHit] = []
    /// The rest that passed the gates, best first.
    var weak: [LookoutHit] = []
    /// The query was a lookup (codes, IDs, long numbers: `Searcher.isLookup`), so words weighed double.
    var isLookup = false
    /// The query's content words (`Searcher.terms`): what to highlight in names, snippets and pages.
    var terms: [String] = []
    /// Whether a query vector took part. False for the keyword-only first pass, and for a final pass whose encoder
    /// failed.
    var usedMeaning = false

    static let empty = LookoutResultSet()

    init() {}

    /// Splits `ranked` (best first) at `strongRatio` of the top score.
    init(ranked: [LookoutHit], terms: [String], isLookup: Bool, usedMeaning: Bool) {
        let strongCount = Searcher.strongCount(ranked)
        strong = Array(ranked.prefix(strongCount))
        weak = Array(ranked.dropFirst(strongCount))
        self.terms = terms
        self.isLookup = isLookup
        self.usedMeaning = usedMeaning
    }

    /// Strong then weak.
    var all: [LookoutHit] { strong + weak }
    var isEmpty: Bool { strong.isEmpty && weak.isEmpty }
    var count: Int { strong.count + weak.count }
}
