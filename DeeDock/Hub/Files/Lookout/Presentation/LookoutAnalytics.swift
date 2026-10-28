import Foundation

/// Lookout's analytics, built from results only: section, rank, kind and match tokens, scope, whether the query was a
/// lookup, and whether it was words or a picture. Nothing here takes the query, the picture, a name or a path, and
/// `AnalyticsValue` can't carry text anyway.
enum LookoutAnalytics {
    /// `lookout_result_opened` for a Lookout hit.
    ///
    /// - Parameters:
    ///   - section: `.strong` or `.weak`.
    ///   - rank: 1-based within its section.
    ///   - query: `.image` for a search with a picture, where `rank` counts within the hit's group; `.imageWords`
    ///     when words were typed beside it.
    ///   - wordsWeight: The picture–words slider's place, 0…1, for `.imageWords`; sent in whole percent.
    static func opened(_ hit: LookoutHit, section: AnalyticsLookoutSection, rank: Int,
                       scope: AnalyticsHubSearchScope, isLookup: Bool,
                       query: AnalyticsLookoutQuery = .text, wordsWeight: Double? = nil) -> AnalyticsEvent {
        .lookoutResultOpened(section: section, rank: rank, kind: AnalyticsLookoutKind(hit),
                             match: AnalyticsLookoutMatch(hit.match), scope: scope, isLookup: isLookup, query: query,
                             wordsWeight: query == .imageWords ? wordsWeight.map { Int(($0 * 100).rounded()) } : nil)
    }

    /// `lookout_result_opened` for a Spotlight name result opened while Lookout was on, so name opens compare with
    /// Lookout's. A name result has no Lookout kind or match, and a search with a picture lists no names.
    static func openedName(rank: Int, scope: AnalyticsHubSearchScope, isLookup: Bool) -> AnalyticsEvent {
        .lookoutResultOpened(section: .names, rank: rank, kind: nil, match: nil, scope: scope, isLookup: isLookup,
                             query: .text)
    }

    /// `lookout_image_search` when a search with a picture starts.
    ///
    /// - Parameter cold: The picture reader had to load first. False for Find Similar on a file in the index, which
    ///   reads nothing.
    static func imageSearch(source: AnalyticsLookoutImageSource, cold: Bool) -> AnalyticsEvent {
        .lookoutImageSearch(source: source, cold: cold)
    }

    /// The counter for a search that ends with Lookout in `phase` showing `results`: shown or empty once its final
    /// results arrived, nothing while they hadn't.
    static func searchCounter(phase: LookoutSearch.Phase, results: LookoutResultSet) -> AnalyticsCounter? {
        guard phase == .done else { return nil }
        return results.isEmpty ? .lookoutSearchWithoutResults : .lookoutSearchWithResults
    }
}

extension AnalyticsLookoutKind {
    nonisolated init(_ hit: LookoutHit) {
        if hit.isFolder {
            self = .folder
            return
        }
        switch hit.kind {
        case .screenshot: self = .screenshot
        case .image: self = .image
        case .pdf: self = .pdf
        case .doc, nil: self = .doc
        }
    }
}

extension AnalyticsLookoutMatch {
    nonisolated init(_ match: LookoutHit.Match) {
        switch match {
        case .meaning: self = .meaning
        case .words: self = .words
        case .both: self = .both
        }
    }
}
