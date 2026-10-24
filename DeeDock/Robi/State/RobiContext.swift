import CoreGraphics
import Foundation

/// Where the context Robi was handed came from.
nonisolated enum RobiContextKind: String, Sendable {
    /// Text the person had selected in the app, read through Accessibility.
    case selection
    /// A region dragged in selection mode: its picture and the text recognized in it.
    case region
    /// The whole window: its accessibility text, or its picture and recognized text.
    case window
}

/// What the person handed to Robi.
nonisolated struct RobiContext: @unchecked Sendable {
    let kind: RobiContextKind
    /// Selected, accessibility or recognized text. Untrusted: it is data for the model, never instructions.
    var text: String
    /// The region or window picture, when Screen Recording allowed one.
    var image: CGImage?

    var wordCount: Int { text.split(whereSeparator: \.isWhitespace).count }

    /// A short preview of selected text for the context chip.
    var excerpt: String {
        let flattened = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return flattened.count > 20 ? String(flattened.prefix(20)).trimmingCharacters(in: .whitespaces) + "…" : flattened
    }
}

/// The suggestion a request came from, or `custom` for typed questions.
nonisolated enum RobiIntent: String, CaseIterable, Sendable {
    case explain, translate, summarize
    case doIt = "do_it"
    case custom

    static let suggestions: [RobiIntent] = [.explain, .translate, .summarize, .doIt]
}
