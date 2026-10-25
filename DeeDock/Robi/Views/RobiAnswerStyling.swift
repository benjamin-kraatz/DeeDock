import SwiftUI

/// Styles the revealed answer text for the card: Markdown's inline styles, web links, and
/// references to landmarks.
///
/// Styles are written over the pacer's text by character offset, so they never add or remove
/// characters and never change what the pacer has revealed. A run still being revealed is styled
/// as far as it goes. Links colour their fading words in the link colour at the fade's opacity, so
/// they never switch colour when the fade ends.
enum RobiAnswerStyling {
    /// How much lighter a reference's dotted underline is than its words, so it reads as clickable
    /// without the weight of a web link.
    static let underlineOpacity = 0.45

    /// - Parameters:
    ///   - paced: The pacer's revealed text: a prefix of `markdown.text`, with fading words.
    ///   - markdown: The formatted answer the text belongs to.
    static func styled(_ paced: AttributedString, markdown: RobiMarkdown) -> AttributedString {
        var text = paced
        let count = text.characters.count
        func revealed(_ range: Range<Int>) -> Range<AttributedString.Index>? {
            guard range.lowerBound < count, !range.isEmpty else { return nil }
            let lower = text.characters.index(text.startIndex, offsetBy: range.lowerBound)
            let upper = text.characters.index(text.startIndex, offsetBy: min(range.upperBound, count))
            return lower..<upper
        }

        for span in markdown.spans {
            guard let range = revealed(span.range) else { continue }
            switch span.style {
            case .strong: addIntent(.stronglyEmphasized, to: range, in: &text)
            case .emphasis: addIntent(.emphasized, to: range, in: &text)
            case .code:
                addIntent(.code, to: range, in: &text)
                text[range].backgroundColor = Color.primary.opacity(0.08)
            case .strikethrough:
                text[range].strikethroughStyle = .single
            case let .link(url):
                text[range].link = url
                colourLink(range, in: &text, underline: false)
            }
        }
        for reference in markdown.references {
            guard let range = revealed(reference.range), let url = RobiReferenceLink.url(reference.landmark) else { continue }
            text[range].link = url
            colourLink(range, in: &text, underline: true)
        }
        return text
    }

    /// Adds an inline intent to every run in `range`, keeping the intents a run already has, so
    /// bold inside italics stays both.
    private static func addIntent(_ intent: InlinePresentationIntent, to range: Range<AttributedString.Index>,
                                  in text: inout AttributedString) {
        // Collected before the writes below: changing attributes keeps indices valid, but not a
        // runs view being iterated.
        let runs = text[range].runs.map { ($0.range, $0.inlinePresentationIntent ?? []) }
        for (run, existing) in runs { text[run].inlinePresentationIntent = existing.union(intent) }
    }

    /// The accent colour at each run's fade, and for a reference, a lighter dotted underline.
    private static func colourLink(_ range: Range<AttributedString.Index>, in text: inout AttributedString, underline: Bool) {
        let fades = text[range].runs.map { ($0.range, $0.robiFade ?? 1) }
        for (run, fade) in fades {
            text[run].foregroundColor = Color.accentColor.opacity(fade)
            text[run].underlineStyle = underline
                ? Text.LineStyle(pattern: .dot, color: Color.accentColor.opacity(underlineOpacity * fade))
                : nil
        }
    }
}
