/// Every number that decides what Lookout's hybrid search finds and in what order, in one place, so tuning one (from
/// PostHog's result-quality events later) is a one-line change. `Searcher` and `LookoutFolderGrouping` read them;
/// nothing else should hard-code them.
///
/// The file values started as DigUp's (`Searcher`, measured on its synthetic and real evals, 2026-10-07 to 10-09).
/// DEE-166 measured them on DOKK's own German and English eval (`LookoutBench eval`, 2026-11-21: 840 files, 2,950
/// cases): `zGate` and `wordWeight` were already at their best, and the values marked DEE-166 below are fitted on its
/// tuning half and checked on the held-out half (MRR 0.404 → 0.514).
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
    /// How much rarer words count for more in that share (`Searcher.patternWeights`); 0 counts every word the same.
    /// DEE-166: 1 beat 0 by a little (+0.003 MRR) and stands in for stopword lists in any language.
    static let idfExponent = 1.0
    /// Lookups (codes, IDs, long numbers: `Searcher.isLookup`) weigh meaning by this and words by twice `wordWeight`.
    static let lookupMeaningWeight = 0.5
    static let lookupWordFactor = 2.0
    /// Added when the file is the kind the query names ("screenshot of…", "pdf").
    static let kindHintBonus = 1.0
    /// How much finding the query's words or codes in the file's own name counts: `nameWeight × name coverage`. An
    /// invoice named after its number then ranks above the corrections that mention it. DEE-166: neutral on generated
    /// queries (they avoid names), and the hand-written set rose from 0.657 to 0.688 at 2.
    static let nameWeight = 2.0
    /// Added when the query names a time (`DateHint`) and the file is from then. DEE-166: date queries rose from 0.478
    /// to 0.612 MRR and level off at 3, where a file from then ranks above every other: a filter that drops nothing.
    static let dateBonus = 3.0
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
    /// them, the bonus capped at `folderBonusCap`. DEE-166: with a bonus up to 1.0 a folder came first for 55% of
    /// queries, above the file they were for (an invoices folder above every invoice in it); without one a folder never
    /// outscores its best file and ranks just below it (MRR 0.372 → 0.455 on the tuning half).
    static let folderBonusPerFile = 0.25
    static let folderBonusCap = 0.0

    /// The numbers a text search ranks with, as one value. `Searcher.tuning` starts from the constants above; the
    /// bench's `eval --set` tries other values on an index without a rebuild, which is how they're fitted (DEE-166).
    struct Tuning: Sendable, Equatable {
        var zGate = LookoutRanking.zGate
        var wordWeight = LookoutRanking.wordWeight
        var coverageExponent = LookoutRanking.coverageExponent
        var wordGate = LookoutRanking.wordGate
        var idfExponent = LookoutRanking.idfExponent
        var lookupMeaningWeight = LookoutRanking.lookupMeaningWeight
        var lookupWordFactor = LookoutRanking.lookupWordFactor
        var kindHintBonus = LookoutRanking.kindHintBonus
        var nameWeight = LookoutRanking.nameWeight
        var dateBonus = LookoutRanking.dateBonus
        var strongRatio = LookoutRanking.strongRatio
        var folderMinimumFiles = LookoutRanking.folderMinimumFiles
        var folderBonusPerFile = LookoutRanking.folderBonusPerFile
        var folderBonusCap = LookoutRanking.folderBonusCap
    }
}
