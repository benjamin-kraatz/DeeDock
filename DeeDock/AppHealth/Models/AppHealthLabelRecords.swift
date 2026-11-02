import Foundation

/// The `prompt` record: a labelling question was shown, or the person picked an app from the menu bar.
///
/// Written when the prompt appears, before any answer, so a prompt that is never answered still leaves a trace.
nonisolated struct AppHealthPromptRecord: Codable, Sendable, Equatable {
    /// Shared with the `label` record that answers this prompt.
    var id: String
    var app: String
    var kind: AppHealthAppKind
    var trigger: AppHealthPromptTrigger
    /// Every suspicion flag that held. Empty for `ordinary` and `manual` prompts.
    var reasons: [AppHealthPromptReason]
    var anchor: AppHealthAnchorKind

    init(id: UUID, app: String, kind: AppHealthAppKind, trigger: AppHealthPromptTrigger,
         reasons: [AppHealthPromptReason], anchor: AppHealthAnchorKind) {
        self.id = id.uuidString
        self.app = app
        self.kind = kind
        self.trigger = trigger
        self.reasons = reasons
        self.anchor = anchor
    }
}

/// The `label` record: the answer to one prompt, covering the window `from`…`to`.
nonisolated struct AppHealthLabelRecord: Codable, Sendable, Equatable {
    /// The `prompt` record's `id`.
    var id: String
    var app: String
    var answer: AppHealthAnswer
    var detail: AppHealthAnswerDetail?
    /// Start of the labelled window, Unix seconds.
    var from: Double
    /// End of the labelled window, Unix seconds.
    var to: Double
    var source: AppHealthLabelSource
    /// Seconds between the prompt appearing and the answer.
    var responseSeconds: Double
    /// The person closed the prompt explicitly.
    var dismissed: Bool
    /// Sleep, turning collection off, or quitting closed the prompt.
    var interrupted: Bool

    init(id: UUID, app: String, answer: AppHealthAnswer, detail: AppHealthAnswerDetail? = nil,
         from: Date, to: Date, source: AppHealthLabelSource, responseSeconds: Double,
         dismissed: Bool = false, interrupted: Bool = false) {
        self.id = id.uuidString
        self.app = app
        self.answer = answer
        self.detail = detail
        self.from = AppHealthRounding.timestamp(from)
        self.to = AppHealthRounding.timestamp(to)
        self.source = source
        self.responseSeconds = AppHealthRounding.seconds(responseSeconds)
        self.dismissed = dismissed
        self.interrupted = interrupted
    }
}
