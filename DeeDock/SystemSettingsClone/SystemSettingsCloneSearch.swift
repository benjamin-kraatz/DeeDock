import Foundation

/// One ranked search hit.
struct SystemSettingsCloneSearchResult: Identifiable, Equatable {
    let pane: SystemSettingsClonePane
    let category: SystemSettingsCloneCategory
    let score: Int
    /// Character offsets in the localized title that matched, for highlighting.
    let highlightedOffsets: IndexSet

    var id: String { pane.id }
}

/// Ranks catalog panes against a free-text query.
///
/// Every query word must match some field of a pane. A word scores highest in the title
/// (exact, then prefix, then word start, then substring), lower in lookup hints and the
/// description, and lowest as a scattered subsequence of the title, which tolerates
/// dropped letters such as "blutooth". Matching ignores case and diacritics, so "ubersicht"
/// finds "Übersicht".
struct SystemSettingsCloneSearchIndex {
    private struct Entry {
        let pane: SystemSettingsClonePane
        let category: SystemSettingsCloneCategory
        let order: Int
        let title: [Character]
        let titleText: String
        let detail: String
        let categoryTitle: String
        let hints: [String]
        let identifier: String
    }

    private let entries: [Entry]

    /// Resolves localized strings once. Rebuild the index if the UI language changes.
    init(categories: [SystemSettingsCloneCategory] = SystemSettingsDeepLinkCatalog.categories) {
        var entries: [Entry] = []
        for category in categories {
            let categoryTitle = Self.fold(String(localized: category.title))
            for pane in category.panes {
                let title = Self.fold(String(localized: pane.title))
                entries.append(Entry(
                    pane: pane,
                    category: category,
                    order: entries.count,
                    title: Array(title),
                    titleText: title,
                    detail: Self.fold(String(localized: pane.detail)),
                    categoryTitle: categoryTitle,
                    hints: pane.searchHints.map { Self.fold($0) },
                    identifier: Self.fold("\(pane.paneIdentifier) \(pane.anchor ?? "")")
                ))
            }
        }
        self.entries = entries
    }

    /// Results ordered best first; empty for a blank query.
    func search(_ query: String) -> [SystemSettingsCloneSearchResult] {
        let folded = Self.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        let words = folded.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }

        let scored: [(entry: Entry, score: Int, offsets: IndexSet)] = entries.compactMap { entry in
            var total = 0
            var offsets = IndexSet()
            for word in words {
                guard let match = Self.score(word, in: entry) else { return nil }
                total += match.score
                offsets.formUnion(match.offsets)
            }
            // Reward the whole phrase leading the title, so "screen t" prefers Screen Time.
            if words.count > 1, entry.titleText.hasPrefix(folded) { total += 400 }
            return (entry, total, offsets)
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.entry.title.count != rhs.entry.title.count {
                    return lhs.entry.title.count < rhs.entry.title.count
                }
                return lhs.entry.order < rhs.entry.order
            }
            .map {
                SystemSettingsCloneSearchResult(
                    pane: $0.entry.pane,
                    category: $0.entry.category,
                    score: $0.score,
                    highlightedOffsets: $0.offsets
                )
            }
    }

    // MARK: Scoring

    private static func score(_ word: String, in entry: Entry) -> (score: Int, offsets: IndexSet)? {
        let wordLength = word.count
        if let range = entry.titleText.range(of: word) {
            let start = entry.titleText.distance(from: entry.titleText.startIndex, to: range.lowerBound)
            let offsets = IndexSet(integersIn: start ..< start + wordLength)
            if entry.titleText == word { return (1000, offsets) }
            if start == 0 { return (800, offsets) }
            if isWordStart(entry.title, at: start) { return (650, offsets) }
            if let later = wordStartOccurrence(of: word, in: entry.title) {
                return (650, IndexSet(integersIn: later ..< later + wordLength))
            }
            return (450, offsets)
        }

        var best: Int?
        func consider(_ value: Int) { best = max(best ?? value, value) }

        for hint in entry.hints {
            if hint.hasPrefix(word) { consider(hint == word ? 520 : 420) }
            else if containsWordPrefix(word, in: hint) { consider(360) }
            else if wordLength >= 3, hint.contains(word) { consider(260) }
        }
        if containsWordPrefix(word, in: entry.detail) { consider(240) }
        else if wordLength >= 3, entry.detail.contains(word) { consider(120) }
        if containsWordPrefix(word, in: entry.categoryTitle) { consider(160) }
        if wordLength >= 4, entry.identifier.contains(word) { consider(60) }
        if let best { return (best, []) }

        if wordLength >= 3, let fuzzy = subsequence(word, in: entry.title) {
            return (fuzzy.score, fuzzy.offsets)
        }
        return nil
    }

    /// Matches letters in order with gaps; tighter matches that start at word boundaries score higher.
    private static func subsequence(_ word: String, in title: [Character]) -> (score: Int, offsets: IndexSet)? {
        var offsets = IndexSet()
        var cursor = 0
        var gaps = 0
        for character in word {
            var found: Int?
            while cursor < title.count {
                defer { cursor += 1 }
                if title[cursor] == character { found = cursor; break }
            }
            guard let found else { return nil }
            if let last = offsets.last, found > last + 1 { gaps += found - last - 1 }
            offsets.insert(found)
        }
        guard let first = offsets.first, gaps <= word.count else { return nil }
        let boundaryBonus = isWordStart(title, at: first) ? 40 : 0
        return (max(20, 140 - gaps * 14 + boundaryBonus), offsets)
    }

    private static func isWordStart(_ characters: [Character], at offset: Int) -> Bool {
        offset == 0 || !(characters[offset - 1].isLetter || characters[offset - 1].isNumber)
    }

    private static func wordStartOccurrence(of word: String, in characters: [Character]) -> Int? {
        let needle = Array(word)
        guard needle.count <= characters.count else { return nil }
        for start in 0 ... characters.count - needle.count where isWordStart(characters, at: start) {
            if Array(characters[start ..< start + needle.count]) == needle { return start }
        }
        return nil
    }

    private static func containsWordPrefix(_ word: String, in text: String) -> Bool {
        wordStartOccurrence(of: word, in: Array(text)) != nil
    }

    /// Case- and diacritic-insensitive form. Keeps one output character per input character,
    /// which title highlighting relies on.
    static func fold(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return folded.count == text.count ? folded : text.lowercased()
    }
}
