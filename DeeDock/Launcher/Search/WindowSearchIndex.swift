import Foundation

/// Matches live window metadata or saved capsules for the Hub's Apps-tab search.
nonisolated enum WindowSearchIndex {
    /// Ranks one scope's matches, best first. Nothing is persisted: the caller owns every source and result.
    ///
    /// - Parameters:
    ///   - query: The user's query. Every substantive word must occur in a result.
    ///   - scope: `.live` searches `sources`; `.saved` searches `saved`.
    ///   - sources: Window metadata copied when the Hub search opened.
    ///   - saved: Saved Session Capsules. "Yesterday" in the query limits them to yesterday's capsules
    ///     and yields no live results.
    @concurrent static func results(query: String, scope: WindowSearchScope, sources: [WindowSearchSource],
        saved: [SessionCapsule]) async -> [WindowSearchResult] {
        let yesterday = WindowSearchMatcher.wantsYesterday(query)
        if yesterday && scope != .saved { return [] }
        var results: [WindowSearchResult] = []
        switch scope {
        case .live:
            results = sources.compactMap { source in
                let text = String(source.title.prefix(1_000)) + "\n" + source.applicationName
                guard let score = WindowSearchMatcher.score(query, in: text) else { return nil }
                return WindowSearchResult(id: source.id, title: source.title, applicationName: source.applicationName,
                    evidence: .metadata, excerpt: WindowSearchMatcher.excerpt(text, query: query), score: score,
                    date: nil, source: source, capsuleID: nil)
            }
        case .saved:
            results = saved.compactMap { capsule in
                if yesterday && !Calendar.current.isDateInYesterday(capsule.createdAt) { return nil }
                let fields = [capsule.title, capsule.summary, capsule.note, capsule.breadcrumb?.nextStep ?? ""]
                    + capsule.unfinishedTasks.prefix(6)
                    + capsule.windows.prefix(12).map { $0.applicationName + " " + ($0.windowTitle ?? "") }
                let text = fields.map { String($0.prefix(2_000)) }.joined(separator: "\n")
                let metadataScore = WindowSearchMatcher.score(query, in: text)
                let ocr = capsule.windows.prefix(12).compactMap { $0.textPreview }.map { String($0.prefix(2_000)) }.joined(separator: "\n")
                guard let score = metadataScore ?? WindowSearchMatcher.score(query, in: text + "\n" + ocr) else { return nil }
                return WindowSearchResult(id: capsule.id, title: capsule.title, applicationName: "",
                    evidence: metadataScore == nil ? .historicalOCR : .capsule,
                    excerpt: WindowSearchMatcher.excerpt(metadataScore == nil ? ocr : text, query: query), score: score,
                    date: capsule.createdAt, source: nil, capsuleID: capsule.id)
            }
        }
        return results.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.title != $1.title { return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            if $0.applicationName != $1.applicationName { return $0.applicationName < $1.applicationName }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
