import ApplicationServices
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
    /// What Robi read, with where each piece sits in the window, so the answer can point at it.
    /// Empty for a selection.
    var landmarks: [RobiLandmark] = []
    /// The Accessibility elements a proposed step may act on, by landmark number. Only landmarks
    /// read from the accessibility tree have one; recognized text never does. Kept as long as
    /// the context, including while its answer is set aside, and released with it.
    var elements: [Int: AXUIElement] = [:]
    /// The window's size when the context was read, in points. Zero for a selection.
    var windowSize: CGSize = .zero
    /// The whole window's picture was taken because its accessibility text was too thin, not
    /// because the person asked for pictures. Such a picture stays when Attach Picture is off.
    var pictureIsFallback = false

    init(kind: RobiContextKind, text: String, image: CGImage? = nil, landmarks: [RobiLandmark] = [],
         elements: [Int: AXUIElement] = [:], windowSize: CGSize = .zero, pictureIsFallback: Bool = false) {
        self.kind = kind
        self.text = text
        self.image = image
        self.landmarks = landmarks
        self.elements = elements
        self.windowSize = windowSize
        self.pictureIsFallback = pictureIsFallback
    }

    var wordCount: Int { text.split(whereSeparator: \.isWhitespace).count }

    func landmark(_ id: Int) -> RobiLandmark? { landmarks.first { $0.id == id } }

    /// A short preview of selected text for the context chip.
    var excerpt: String {
        let flattened = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return flattened.count > 20 ? String(flattened.prefix(20)).trimmingCharacters(in: .whitespaces) + "…" : flattened
    }
}

/// The suggestion a request came from: a built-in action, a question Apple Intelligence suggested
/// (`suggested`), or a typed question (`custom`).
nonisolated enum RobiIntent: String, CaseIterable, Sendable {
    case explain, translate, summarize
    case doIt = "do_it"
    /// Fix spelling, grammar and punctuation, keeping the wording.
    case proofread
    case improve
    case shorten
    case formal
    case friendly
    /// Draft a reply to a message, as the person.
    case reply
    /// List the to-dos in the context.
    case actionItems = "action_items"
    /// A question the on-device model suggested for this context. Answered like a typed one.
    case suggested
    case custom

    /// Built-in actions in the order the row offers them for this context. An editable selection
    /// leads with rewriting; anything read-only leads with understanding. The row shows as many
    /// leading actions as fit and puts the rest in its More menu, where `group` separates them.
    static func actions(canReplace: Bool) -> [RobiIntent] {
        canReplace
            ? [.proofread, .improve, .translate, .shorten, .formal, .friendly, .explain, .summarize, .actionItems, .reply, .doIt]
            : [.explain, .summarize, .translate, .doIt, .actionItems, .reply, .proofread, .improve, .shorten, .formal, .friendly]
    }

    /// Kinds of action, for the separators in the More menu.
    enum Group { case understand, rewrite, act, question }

    var group: Group {
        switch self {
        case .explain, .summarize, .actionItems: .understand
        case .translate, .proofread, .improve, .shorten, .formal, .friendly: .rewrite
        case .doIt, .reply: .act
        case .suggested, .custom: .question
        }
    }

    /// The agent gets the app's menu commands and the window's controls, and may propose steps.
    var canAct: Bool { self == .doIt || self == .suggested || self == .custom }
}
