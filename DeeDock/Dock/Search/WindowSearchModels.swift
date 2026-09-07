import AppKit

/// Search scopes are explicit. Saved capsules never become evidence about a current window.
nonisolated enum WindowSearchScope: String, CaseIterable, Identifiable {
    case live, captured, saved
    var id: Self { self }
    var title: LocalizedStringResource {
        switch self {
        case .live: .windowSearchLive
        case .captured: .windowSearchCaptured
        case .saved: .windowSearchSaved
        }
    }
}

/// Immutable metadata copied at search opening. AX tokens belong to the search service alone.
nonisolated struct WindowSearchSource: Identifiable, Sendable {
    let id: UUID
    let applicationName: String
    let processIdentifier: pid_t
    let launchDate: Date?
    let window: ApplicationWindowSummary?
    let candidate: WindowContextCandidate?
    var title: String { window?.title ?? candidate?.title ?? applicationName }
}

/// Literal evidence is separate from image-model suggestions, including their sort priority.
nonisolated enum WindowSearchEvidence: Sendable {
    case metadata, text, capsule, image
    var label: LocalizedStringResource {
        switch self {
        case .metadata: .windowSearchMetadataEvidence
        case .text: .windowSearchTextEvidence
        case .capsule: .windowSearchCapsuleEvidence
        case .image: .windowSearchImageEvidence
        }
    }
}

nonisolated struct WindowSearchResult: Identifiable, Sendable {
    let id: UUID
    let title: String
    let applicationName: String
    let evidence: WindowSearchEvidence
    let excerpt: String
    let score: Int
    let date: Date?
    let source: WindowSearchSource?
    let capsuleID: UUID?
}

/// A bounded literal matcher. It never derives a color or other image attribute from OCR.
nonisolated enum WindowSearchMatcher {
    static let maximumQuery = 200
    static let maximumText = 6_000
    static let maximumCaptures = 4
    static let maximumSources = 200

    static func wantsYesterday(_ query: String) -> Bool {
        words(query).contains { $0 == "yesterday" || $0 == "gestern" }
    }

    static func terms(_ query: String) -> [String] {
        let ignored: Set<String> = ["the", "a", "an", "with", "window", "der", "die", "das", "mit", "fenster", "yesterday", "gestern"]
        return words(String(query.prefix(maximumQuery))).filter { !ignored.contains($0) }
    }

    /// All substantive words must occur. Phrase matches rank ahead of scattered word matches.
    static func score(_ query: String, in text: String) -> Int? {
        let terms = terms(query)
        let haystack = normalized(text)
        guard terms.allSatisfy({ haystack.contains($0) }) else { return nil }
        return terms.isEmpty ? 0 : (haystack.contains(terms.joined(separator: " ")) ? 100 : 60)
    }

    static func excerpt(_ text: String, query: String) -> String {
        guard let term = terms(query).first,
              let range = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(text.prefix(220))
        }
        let start = text.index(range.lowerBound, offsetBy: -60, limitedBy: text.startIndex) ?? text.startIndex
        return (start == text.startIndex ? "" : "…") + String(text[start...].prefix(220))
    }

    private static func words(_ text: String) -> [String] {
        normalized(text).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
