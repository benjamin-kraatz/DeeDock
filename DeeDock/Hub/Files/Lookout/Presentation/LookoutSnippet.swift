import Foundation

/// A Lookout snippet split into plain runs and matched runs, for highlighting.
///
/// `LookoutHit.snippet` marks the query's words « like this », as SQLite's `snippet()` and `SearchText.snippet` do.
/// The markers are never shown: each marked run becomes a highlighted run. A stray "»" is dropped, and an unclosed
/// "«" highlights to the end. Runs are never empty; neighbouring runs of the same kind are merged.
nonisolated struct LookoutSnippet: Equatable, Sendable {
    /// One run of text.
    struct Run: Equatable, Sendable {
        let text: String
        /// The run is one of the query's words.
        let isMatch: Bool
    }

    static let open: Character = "«"
    static let close: Character = "»"

    let runs: [Run]

    /// The text as shown, without markers.
    var text: String { runs.map(\.text).joined() }
    var hasMatches: Bool { runs.contains(where: \.isMatch) }

    /// Parses a marked snippet.
    init(marked: String) {
        var runs: [Run] = []
        var current = ""
        var inMatch = false
        func flush() {
            guard !current.isEmpty else { return }
            if let last = runs.last, last.isMatch == inMatch {
                runs[runs.count - 1] = Run(text: last.text + current, isMatch: inMatch)
            } else {
                runs.append(Run(text: current, isMatch: inMatch))
            }
            current = ""
        }
        for character in marked {
            switch character {
            case Self.open where !inMatch:
                flush()
                inMatch = true
            case Self.close where inMatch:
                flush()
                inMatch = false
            case Self.open, Self.close:
                continue   // a nested « or a stray »: never shown
            default:
                current.append(character)
            }
        }
        flush()
        self.runs = runs
    }

    /// Unmarked text with `terms` highlighted where keyword search would find them (`SearchText.matches`): a stored
    /// excerpt, which carries no markers of its own.
    init(text: String, terms: [String]) {
        let marks = terms.flatMap { SearchText.matches(of: $0, in: text) }.sorted { $0.lowerBound < $1.lowerBound }
        var runs: [Run] = []
        var cursor = text.startIndex
        for mark in marks where mark.lowerBound >= cursor {
            if cursor < mark.lowerBound { runs.append(Run(text: String(text[cursor..<mark.lowerBound]), isMatch: false)) }
            runs.append(Run(text: String(text[mark]), isMatch: true))
            cursor = mark.upperBound
        }
        if cursor < text.endIndex { runs.append(Run(text: String(text[cursor...]), isMatch: false)) }
        self.runs = runs
    }

    /// The snippet for a hit: its marked words when they matched there, else its excerpt with the terms highlighted.
    /// Nil when the hit has neither.
    init?(hit: LookoutHit, terms: [String]) {
        if let snippet = hit.snippet, !snippet.isEmpty {
            self.init(marked: snippet)
        } else if let excerpt = hit.excerpt, !excerpt.isEmpty {
            self.init(text: excerpt, terms: terms)
        } else {
            return nil
        }
        if runs.isEmpty { return nil }
    }
}
