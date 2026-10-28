/// Every number that decides what Lookout's hybrid search finds and in what order, in one place, so tuning one (from
/// PostHog's result-quality events later) is a one-line change. `Searcher` and `LookoutFolderGrouping` read them;
/// nothing else should hard-code them.
///
/// The file values are DigUp's (`Searcher`, measured on its synthetic and real evals, 2026-10-07 to 10-09). The folder
/// values are DOKK's own and have not been measured yet.
nonisolated enum LookoutRanking {
    /// A segment counts as a meaning match when it stands this many standard deviations above this query's average
    /// (`Searcher.meaning`).
    static let zGate = 2.0
    /// How much finding all of the query's words counts against meaning: `wordWeight × coverage^1.5`.
    static let wordWeight = 2.0
    /// The exponent on word coverage: half the words are worth well under half the bonus.
    static let coverageExponent = 1.5
    /// A file qualifies by words alone when it has at least this share of the query's words.
    static let wordGate = 0.5
    /// Lookups (codes, IDs, long numbers: `Searcher.isLookup`) weigh meaning by this and words by twice `wordWeight`.
    static let lookupMeaningWeight = 0.5
    static let lookupWordFactor = 2.0
    /// Added when the file is the kind the query names ("screenshot of…", "pdf").
    static let kindHintBonus = 1.0
    /// Hits scoring at least this share of the top score are strong; the rest are folded under weaker matches. On
    /// DigUp's evals 0.5 cut the list from 26.2 to 5.7 results per query and never folded an expected answer.
    static let strongRatio = 0.5

    /// How much typed words count against the picture they're typed beside, 0…1: a file's meaning is
    /// `(1 − w) × z(picture) + w × z(words)`, put on its own scale again (`Searcher.blend`). Measured on 67 labeled
    /// cases ("this, but at night", "in orange", "a tree") and on a real index (2026-10-28, DEE-126): 0.4 put the answer
    /// first in 58% of cases, against 0% for the picture alone and 13% for the words alone. Attribute changes peak at
    /// 0.4, subject changes ("a tree") nearer 0.7, so people can move it (`pictureWordsWeights`).
    static let pictureWordsWeight = 0.4
    /// The range the picture–words slider offers. Past either end one side drowns the other.
    static let pictureWordsWeights: ClosedRange<Double> = 0.1...0.9

    /// A folder is a result when at least this many of its direct-child files qualify.
    static let folderMinimumFiles = 3
    /// A folder scores the average of its best `folderMinimumFiles` files, plus this for each matching file beyond
    /// them, the bonus capped at `folderBonusCap`.
    static let folderBonusPerFile = 0.25
    static let folderBonusCap = 1.0
}
