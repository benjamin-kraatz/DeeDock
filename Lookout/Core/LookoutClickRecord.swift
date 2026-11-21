import Foundation

/// One line of the developer click log (`LookoutClickLog` in the app; `LookoutBench clicks` and `rerank --clicks`
/// read it): a Lookout search and how it ended (DEE-166). The app writes it and the bench reads it, so the layout lives
/// here once. Raise `format` with any change old lines can't be read with.
nonisolated struct LookoutClickRecord: Codable, Sendable {
    /// The line layout; `Hit.features` follow `featureVersion`.
    var format = 1
    let at: Date
    /// `open` (something was opened from the results) or `end` (the search ended without an open).
    let event: String
    /// "0.28.0 (81)".
    let app: String
    let query: String
    /// `thisMac`, or the folder searched.
    let scope: String
    /// Where Lookout's search was (`LookoutSearch.Phase`): `done` means the meaning pass had arrived.
    let phase: String
    let usedMeaning: Bool
    let isLookup: Bool
    let terms: [String]
    /// The date range the query names (`DateHint`), when it names one.
    let dateHint: DateInterval?
    let kindHints: [String]
    /// The ranking numbers in use (`LookoutRanking.Tuning`), to tell lines apart across changes.
    let ranking: [String: Double]
    /// `LookoutRerankFeatures.version` of every hit's `features`.
    let featureVersion: Int
    /// Every hit Lookout listed, strong then weak.
    let lookout: [Hit]
    /// Spotlight's name results, best first (at most `nameLimit`).
    let names: [String]
    /// Whether "Weaker matches" was open.
    let weakExpanded: Bool
    /// What was opened; nil for `end`.
    let opened: Opened?

    /// How many name results a line keeps.
    static let nameLimit = 20

    /// A hit as Lookout listed it.
    struct Hit: Codable, Sendable {
        let rank: Int
        /// `strong` or `weak`.
        let section: String
        let path: String
        let kind: String?
        let isFolder: Bool
        let score: Double
        let z: Double?
        let cosine: Double?
        let coverage: Double
        let keywordRank: Int?
        let match: String
        let segment: String?
        let page: Int?
        let hasSnippet: Bool
        /// The reranker's features (`LookoutRerankFeatures.names`).
        let features: [Double]
    }

    /// What was opened.
    struct Opened: Codable, Sendable {
        /// `lookout` or `name`.
        let source: String
        let path: String
        /// 1-based place in its own list (Lookout's strong then weak, or the names).
        let rank: Int
        /// Where Lookout listed the same file (1-based); nil when it didn't. For a name result that's the gap to
        /// look at.
        let lookoutRank: Int?
    }
}
