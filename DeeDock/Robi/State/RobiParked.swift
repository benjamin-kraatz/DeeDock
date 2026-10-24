import CoreGraphics
import Foundation

/// What the answer card shows for one question. `RobiModel` holds the one on screen; an answer
/// set aside keeps its own copy in `RobiParked`.
struct RobiExchange {
    var context: RobiContext?
    var request = ""
    var answer = ""
    var proposal: RobiProposal?
    var notice: RobiNotice?
    var isStopped = false
    var canReplace = false
    var answerModel: RobiAnswerModel = .onDevice
    /// `.thinking` while the answer is still being written, `.answered` once it is complete.
    var phase: RobiPhase = .thinking
}

/// An answer set aside because the person switched to another window while it was being
/// written or shown.
///
/// The answer keeps generating into `exchange` while its window is in the background, and comes
/// back with the card when that window is focused again. There is one at most: asking Robi
/// something new, closing the window, stopping Robi, or ten minutes drop it, and dropping one that
/// is still being written cancels it the same way Stop does.
@MainActor
struct RobiParked {
    /// The window the answer belongs to.
    let windowID: CGWindowID
    let applicationName: String
    var exchange: RobiExchange
    /// The answer still being written; nil once it is complete.
    var task: Task<Void, Never>?
    /// The answer's generation in `RobiController`, which routes its updates here.
    let generation: Int
    var answering: (intent: RobiIntent, started: Date)?
    /// The selection Replace writes to, kept so Replace still works after coming back.
    let selection: RobiSelection?
    /// A question waiting for an API key, when the answer ended asking for one.
    var pending: (intent: RobiIntent, text: String)?

    /// How long an answer waits for its window before it is dropped.
    static let lifetime: Duration = .seconds(600)
}

/// The dot on Robi's face while an answer waits on another window.
struct RobiParkedBadge: Equatable {
    /// The answer is still being written; otherwise it is ready.
    let isWorking: Bool
    /// The app the answer belongs to, for VoiceOver.
    let applicationName: String
}
