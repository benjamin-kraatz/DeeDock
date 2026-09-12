#if DIRECT_DISTRIBUTION
import Foundation

/// Bilingual What’s New comic parsed from the locked `*-comic.md` shape.
///
/// German panels come first. An `## English` heading starts the matching English
/// copies. Art stays outside the text so DE and EN remain selectable.
nonisolated struct UpdateComic: Sendable, Equatable {
    /// Document title from the leading `#` heading, if present.
    var title: String
    /// Paired panels in document order. The authoring spec allows 2...4.
    var panels: [UpdateComicPanel]
}

/// One panel: shared art plus German and English copy.
nonisolated struct UpdateComicPanel: Identifiable, Sendable, Equatable {
    /// Stable panel number from the heading, such as `01`.
    var id: String
    /// Relative markdown image path, used to resolve art against the document URL.
    var imagePath: String
    /// Decoded PNG bytes after a successful allowlisted fetch, or preview `Data`.
    var imageData: Data?
    var german: UpdateComicCopy
    var english: UpdateComicCopy
}

/// Title, optional speech, caption, and alt for one language.
nonisolated struct UpdateComicCopy: Sendable, Equatable {
    /// Short topic from the panel heading after the em dash, when present.
    var topic: String
    var title: String
    /// Spoken line. Empty when the panel has no voice.
    var speech: String
    var caption: String
    var alt: String

    /// Authoring caps from DEE-38 v0. The parser does not reject longer copy.
    nonisolated static let titleWordLimit = 6
    nonisolated static let speechWordLimit = 8
    nonisolated static let captionWordLimit = 32

    /// Counts whitespace-separated words in this language’s field.
    nonisolated func wordCount(of text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}

/// Parses the locked What’s New comic markdown. No HTML, CSS, or network I/O.
nonisolated enum UpdateComicParser {
    nonisolated static let maximumPanelCount = 4

    /// Returns a comic when German and English panels pair, otherwise `nil`.
    ///
    /// Parsing stays off the main actor. Callers cancel by discarding the result.
    nonisolated static func parse(_ markdown: String) -> UpdateComic? {
        guard markdown.utf8.count <= UpdateReleaseNotes.maximumBytes else { return nil }
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        guard let englishIndex = lines.firstIndex(where: { isEnglishHeading($0) }) else { return nil }

        let title = headingText(lines.first(where: { $0.hasPrefix("# ") && !$0.hasPrefix("##") }) ?? "")
        let germanPanels = panels(in: Array(lines[..<englishIndex]))
        let englishPanels = panels(in: Array(lines[englishIndex...].dropFirst()))
        guard !germanPanels.isEmpty else { return nil }

        var paired: [UpdateComicPanel] = []
        for german in germanPanels.prefix(maximumPanelCount) {
            guard let english = englishPanels.first(where: { $0.id == german.id }) else { continue }
            guard !german.copy.title.isEmpty, !english.copy.title.isEmpty else { continue }
            paired.append(UpdateComicPanel(id: german.id, imagePath: german.imagePath,
                                           imageData: nil, german: german.copy, english: english.copy))
        }
        guard paired.count >= 1 else { return nil }
        return UpdateComic(title: title, panels: paired)
    }

    nonisolated private static func isEnglishHeading(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == "## English"
    }

    nonisolated private static func headingText(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        while text.hasPrefix("#") { text.removeFirst() }
        return text.trimmingCharacters(in: .whitespaces)
    }

    fileprivate struct DraftPanel {
        var id: String
        var imagePath: String
        var copy: UpdateComicCopy
    }

    nonisolated private static func panels(in lines: [String]) -> [DraftPanel] {
        var result: [DraftPanel] = []
        var currentID: String?
        var currentTopic = ""
        var block: [String] = []

        func flush() {
            guard let id = currentID else { return }
            if let parsed = panel(id: id, topic: currentTopic, lines: block) {
                result.append(parsed)
            }
            currentID = nil
            currentTopic = ""
            block.removeAll()
        }

        for raw in lines {
            if let heading = panelHeading(raw) {
                flush()
                currentID = heading.id
                currentTopic = heading.topic
                continue
            }
            if currentID != nil { block.append(raw) }
        }
        flush()
        return result
    }

    nonisolated private static func panelHeading(_ line: String) -> (id: String, topic: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("##") else { return nil }
        var rest = trimmed
        while rest.hasPrefix("#") { rest.removeFirst() }
        rest = rest.trimmingCharacters(in: .whitespaces)
        guard rest.lowercased().hasPrefix("panel ") else { return nil }
        let body = rest.dropFirst(6).trimmingCharacters(in: .whitespaces)
        let separator = body.range(of: "—") ?? body.range(of: " - ") ?? body.range(of: " – ")
        let idPart = separator.map { String(body[..<$0.lowerBound]) } ?? String(body)
        let topic = separator.map { String(body[$0.upperBound...]).trimmingCharacters(in: .whitespaces) } ?? ""
        let digits = idPart.trimmingCharacters(in: .whitespaces).filter(\.isNumber)
        guard let value = Int(digits), (1...maximumPanelCount).contains(value) else { return nil }
        return (String(format: "%02d", value), topic)
    }

    nonisolated private static func panel(id: String, topic: String, lines: [String]) -> DraftPanel? {
        var imagePath = ""
        var alt = ""
        var title = ""
        var speechLines: [String] = []
        var captionLines: [String] = []
        var seenImage = false

        for raw in lines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if let image = markdownImage(trimmed) {
                imagePath = image.path
                alt = image.alt
                seenImage = true
                continue
            }
            if title.isEmpty, let bold = boldLine(trimmed) {
                title = bold
                continue
            }
            if trimmed.hasPrefix(">"), title.isEmpty == false, captionLines.allSatisfy({ $0.isEmpty }) {
                var quote = String(trimmed.dropFirst())
                if quote.hasPrefix(" ") { quote.removeFirst() }
                speechLines.append(quote)
                continue
            }
            if seenImage { captionLines.append(trimmed) }
        }

        let caption = captionLines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !imagePath.isEmpty, !title.isEmpty else { return nil }
        return DraftPanel(id: id, imagePath: imagePath,
                          copy: UpdateComicCopy(topic: topic, title: title,
                                                speech: speechLines.joined(separator: "\n"),
                                                caption: caption, alt: alt))
    }

    nonisolated private static func markdownImage(_ line: String) -> (alt: String, path: String)? {
        guard line.hasPrefix("![") else { return nil }
        guard let altEnd = line.firstIndex(of: "]"),
              altEnd < line.endIndex,
              line[line.index(after: altEnd)] == "(" ,
              line.hasSuffix(")") else { return nil }
        let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<altEnd])
        let pathStart = line.index(altEnd, offsetBy: 2)
        let pathEnd = line.index(before: line.endIndex)
        let path = String(line[pathStart..<pathEnd]).trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return nil }
        return (alt, path)
    }

    nonisolated private static func boldLine(_ line: String) -> String? {
        guard line.hasPrefix("**"), line.hasSuffix("**"), line.count >= 4 else { return nil }
        return String(line.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
    }
}
#endif
