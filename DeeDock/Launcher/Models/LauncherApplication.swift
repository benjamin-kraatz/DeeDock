import Foundation

/// Immutable, pre-normalized metadata used by search without filesystem or icon work per keystroke.
nonisolated struct LauncherApplication: Identifiable, Sendable, Equatable {
    let reference: ApplicationReference
    let category: String
    let aliases: [String]
    let searchName: String
    let searchAliases: String
    let initials: String
    var id: String { reference.id }

    init(reference: ApplicationReference, category: String = "", aliases: [String] = []) {
        self.reference = reference
        self.category = category
        self.aliases = aliases
        searchName = Self.normalize(reference.name)
        searchAliases = Self.normalize(([reference.bundleIdentifier ?? "", reference.url.deletingPathExtension().lastPathComponent] + aliases).joined(separator: " "))
        initials = searchName.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).compactMap(\.first).map(String.init).joined()
    }

    static func normalize(_ text: String) -> String {
        let visible = String(String.UnicodeScalarView(text.unicodeScalars.filter { $0.properties.generalCategory != .format }))
        return visible.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Exact name, prefix, words, initials, and metadata rank before one-edit typo matches.
    func score(_ query: String) -> Int? {
        guard !query.isEmpty else { return 0 }
        if searchName == query { return 0 }
        if searchName.hasPrefix(query) { return 10 }
        if searchName.contains(query) { return 20 }
        if initials == query { return 25 }
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        if terms.allSatisfy({ searchName.contains($0) || searchAliases.contains($0) }) { return 30 }
        let words = searchName.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if terms.allSatisfy({ term in
            words.contains { $0.hasPrefix(term) || (term.count >= 4 && Self.oneEditApart(term, $0)) }
        }) { return 50 }
        return nil
    }

    private static func oneEditApart(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs), b = Array(rhs)
        guard abs(a.count - b.count) <= 1 else { return false }
        var i = 0, j = 0, edits = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] { i += 1; j += 1; continue }
            edits += 1
            guard edits <= 1 else { return false }
            if a.count == b.count, i + 1 < a.count, a[i] == b[j + 1], a[i + 1] == b[j] {
                i += 2; j += 2
            } else if a.count < b.count { j += 1 }
            else if a.count > b.count { i += 1 }
            else { i += 1; j += 1 }
        }
        return edits + (a.count - i) + (b.count - j) <= 1
    }
}
