import Foundation

nonisolated enum WindowSearchIndex {
    /// No persistent index: closing the presentation releases every document and result.
    @concurrent static func results(query: String, scope: WindowSearchScope, sources: [WindowSearchSource],
        snapshots: [WindowContextSnapshot], owners: [UInt32: WindowSearchSource], date: Date?,
        saved: [SessionCapsule], images: [WindowSearchResult]) async -> [WindowSearchResult] {
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
        case .captured:
            results = snapshots.compactMap { snapshot in
                guard let source = owners[snapshot.candidate.id] else { return nil }
                let metadata = String(source.title.prefix(1_000)) + "\n" + source.applicationName
                let metadataScore = WindowSearchMatcher.score(query, in: metadata)
                let combined = metadata + "\n" + snapshot.recognizedText
                guard let score = metadataScore ?? WindowSearchMatcher.score(query, in: combined) else { return nil }
                return WindowSearchResult(id: source.id, title: source.title, applicationName: source.applicationName,
                    evidence: metadataScore == nil ? .text : .metadata,
                    excerpt: WindowSearchMatcher.excerpt(metadataScore == nil ? snapshot.recognizedText : metadata, query: query),
                    score: score + (metadataScore == nil ? 0 : 20), date: date, source: source, capsuleID: nil)
            }
            let literalIDs = Set(results.map(\.id))
            results += images.filter { !literalIDs.contains($0.id) }
        case .saved:
            results = saved.compactMap { capsule in
                if yesterday && !Calendar.current.isDateInYesterday(capsule.createdAt) { return nil }
                let fields = [capsule.title, capsule.summary, capsule.note, capsule.breadcrumb?.nextStep ?? ""]
                    + capsule.unfinishedTasks.prefix(6)
                    + capsule.windows.prefix(12).map { $0.applicationName + " " + ($0.windowTitle ?? "") }
                let text = fields.map { String($0.prefix(2_000)) }.joined(separator: "\n")
                guard let score = WindowSearchMatcher.score(query, in: text) else { return nil }
                return WindowSearchResult(id: capsule.id, title: capsule.title, applicationName: "",
                    evidence: .capsule, excerpt: WindowSearchMatcher.excerpt(text, query: query), score: score,
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
