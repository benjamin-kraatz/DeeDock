import AppKit
import Observation
import SwiftUI

/// What Robi is doing, from asleep to showing an answer.
enum RobiPhase: Equatable {
    /// Still and quiet: sleepy eyes, no timers or pointer monitors running.
    case idle
    /// Hovered: eyes open and follow the pointer, an occasional blink.
    case awake
    /// No text was selected: the window is dimmed and the person drags a region or clicks it.
    case selecting
    /// The tab became a prompt bar with the context attached and suggestions below it.
    case prompting
    /// A model is answering.
    case thinking
    /// The answer is complete and its actions are enabled.
    case answered

    var isBar: Bool { self == .prompting || self == .thinking || self == .answered }
    var showsCard: Bool { self == .thinking || self == .answered }
    /// Phases in which Robi holds the person's attention, so focus changes end the interaction.
    var isEngaged: Bool { self != .idle && self != .awake }
}

/// Something the answer card says instead of, or before, an answer.
enum RobiNotice: Equatable {
    /// Claude is chosen but no API key is saved.
    case claudeKeyMissing
    /// The on-device model cannot answer on this Mac right now.
    case onDeviceUnavailable(LocalizedStringResource)
    /// Reading pixels needs Screen Recording, which is off.
    case screenRecordingNeeded
    /// The request failed; the message is safe to show.
    case failed(String)
}

/// A menu command the model proposed. Nothing runs until the person clicks it.
struct RobiProposal: Equatable {
    /// The menu path as the app names it, such as "File > New Tab".
    let path: String
}

/// Everything Robi's views draw. Owned by `RobiController`, which is the only writer.
@MainActor @Observable
final class RobiModel {
    var phase: RobiPhase = .idle
    var placement: RobiPlacement = .above
    /// False while the tab retracts into one window before emerging from the next.
    var isPresent = false
    /// The title-bar colour sampled under the tab.
    var tint = Color(nsColor: .windowBackgroundColor)
    var tintIsDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    var applicationName = ""
    var context: RobiContext?
    /// True while a region or window is still being captured and read.
    var isReadingContext = false
    var prompt = ""
    /// Shown in the bar while answering, such as a suggestion's name.
    var request = ""
    var answer = ""
    var proposal: RobiProposal?
    var notice: RobiNotice?
    var toast: LocalizedStringResource?
    /// The person stopped the answer; what arrived before that stays in the card.
    var isStopped = false
    /// An answer is waiting on another window; Robi's face shows a dot for it.
    var parkedBadge: RobiParkedBadge?
    /// A hanging tab pulled away from the window's edge by a Shift-drag: the bulb's sideways lean
    /// and how far down it is pulled, in points. Zero when nothing pulls. See `RobiGoo`.
    var goo: CGSize = .zero
    /// The selection can be replaced in place through Accessibility.
    var canReplace = false
    /// Questions the on-device model suggested for this context, already cleaned. Empty until
    /// they arrive, and for good if suggestions are off, unavailable, or failed.
    var generatedSuggestions: [String] = []
    /// Suggested questions may arrive for this prompt, so the panel keeps room for their row.
    var suggestsQuestions = false
    var answerModel: RobiAnswerModel = .onDevice
    /// The Claude model that answers, named in the card's footer; read only when `answerModel` is
    /// `.claude`.
    var claudeModel: RobiClaudeModel = .sonnet
    var claudeEffort: RobiClaudeEffort = .medium
    /// The Attach Picture switch in the prompt bar, mirrored from `RobiSettings`.
    var attachesWindowPicture = false
    /// Screen Recording allows a picture of the window, checked when the window is read.
    var canAttachPicture = true
    var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    var reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency

    /// The answer with its links to landmarks taken out and kept as references. While the
    /// answer streams, a link that has not fully arrived is held back.
    var referencedAnswer: RobiReferencedAnswer {
        RobiReferencedAnswer(answer, landmarks: Set(context?.landmarks.map(\.id) ?? []),
                             isFinished: phase == .answered || isStopped)
    }

    /// The answer as the card draws it: Markdown syntax taken out and kept as blocks and styles,
    /// references moved along with the text. Syntax that has not fully arrived is held back.
    var formattedAnswer: RobiMarkdown {
        RobiMarkdown(referencedAnswer, isFinished: phase == .answered || isStopped)
    }

    /// The answer as Copy, Replace and Paste put it into the app: references are plain words, and
    /// Markdown stays as written, since a rewrite of Markdown text must keep its syntax.
    var answerText: String {
        RobiReferencedAnswer(answer, landmarks: [], isFinished: true).text
    }

    /// Text and controls on the tab: light on dark title bars, dark on light ones.
    var ink: Color { tintIsDark ? .white : Color(red: 0.13, green: 0.12, blue: 0.17) }
    var rim: Color { tintIsDark ? .white.opacity(0.14) : .black.opacity(0.10) }
    /// The card follows the window's brightness so it reads as part of the same surface.
    var cardIsDark: Bool { tintIsDark }

    var tabWidth: CGFloat {
        switch phase {
        case .idle, .awake: RobiMetrics.tabWidth
        case .selecting: RobiMetrics.selectingWidth
        case .prompting, .thinking, .answered: RobiMetrics.barWidth
        }
    }

    /// The panel's content size for a phase. The panel grows before an animation that needs more
    /// room and shrinks after one that needs less, so its transparent margin never sits over the
    /// window longer than necessary.
    func panelSize(for phase: RobiPhase) -> CGSize {
        let width: CGFloat = switch phase {
        case .idle, .awake: RobiMetrics.tabWidth
        case .selecting: RobiMetrics.selectingWidth
        case .prompting, .thinking, .answered: RobiMetrics.barWidth
        }
        var height = RobiMetrics.tabHeight + RobiMetrics.shadowMargin
        if phase == .prompting {
            height += RobiMetrics.suggestionHeight
            // Reserved before the suggestions arrive, so the panel never resizes for them.
            if suggestsQuestions { height += RobiMetrics.generatedSuggestionHeight }
        }
        if phase.showsCard { height += RobiMetrics.cardHeight }
        return CGSize(width: width + 2 * RobiMetrics.sideMargin, height: height)
    }

    /// The card's content, to set it aside or to change it through `apply(_:)`. Its phase is the
    /// card's own: `.thinking` until the answer is complete.
    var exchange: RobiExchange {
        RobiExchange(context: context, request: request, answer: answer, proposal: proposal, notice: notice,
                     isStopped: isStopped, canReplace: canReplace, answerModel: answerModel, claudeModel: claudeModel,
                     phase: phase == .answered ? .answered : .thinking)
    }

    /// Writes back what a streamed update can change. Only fields that differ are set, so a new
    /// chunk of answer redraws the answer and nothing else. The phase is the controller's to set.
    func apply(_ exchange: RobiExchange) {
        if answer != exchange.answer { answer = exchange.answer }
        if proposal != exchange.proposal { proposal = exchange.proposal }
        if notice != exchange.notice { notice = exchange.notice }
        if isStopped != exchange.isStopped { isStopped = exchange.isStopped }
    }

    /// Shows an answer that was set aside, replacing whatever the card held.
    func restore(_ exchange: RobiExchange) {
        resetInteraction()
        context = exchange.context
        request = exchange.request
        answer = exchange.answer
        proposal = exchange.proposal
        notice = exchange.notice
        isStopped = exchange.isStopped
        canReplace = exchange.canReplace
        answerModel = exchange.answerModel
        claudeModel = exchange.claudeModel
    }

    /// Clears everything an interaction left behind. An answer set aside on another window and
    /// its `parkedBadge` are not part of it.
    func resetInteraction() {
        context = nil
        isReadingContext = false
        prompt = ""
        request = ""
        answer = ""
        proposal = nil
        notice = nil
        toast = nil
        isStopped = false
        canReplace = false
        generatedSuggestions = []
        suggestsQuestions = false
    }
}

/// Where Robi's pupils point and whether it is mid-blink.
///
/// Kept apart from `RobiModel` so pointer updates redraw only the face, not the prompt bar or card.
@MainActor @Observable
final class RobiEyes {
    /// Offset of both pupils, in tenths of an eye width. Zero looks straight ahead.
    var pupil: CGSize = CGSize(width: 0, height: 2)
    var isBlinking = false
    /// Set for a moment after the pointer circled the face: the pupils spin and the mouth
    /// rounds into an "o".
    var dizzy: RobiDizzy?
    /// Set for a moment when a picked region lands in the face: the eyes widen, the pupils
    /// jump, and the mouth rounds. The controller clears `dizzy` when it sets this.
    var surprised: RobiSurprise?
}

/// What Robi's views can ask the controller to do.
struct RobiActions {
    /// Clicks the face. VoiceOver's default action; a pointer click goes through `faceGesture`.
    var tapFace: () -> Void = {}
    /// The pointer pressing, dragging, or releasing the face. The controller tells a click from a
    /// drag of the tab along the window's top edge.
    var faceGesture: (RobiFaceGesture) -> Void = { _ in }
    var submit: (String) -> Void = { _ in }
    var suggest: (RobiIntent) -> Void = { _ in }
    /// Asks one of the suggested questions, like a typed one.
    var askSuggested: (String) -> Void = { _ in }
    var copy: () -> Void = {}
    var replace: () -> Void = {}
    var paste: () -> Void = {}
    var runProposal: () -> Void = {}
    /// Spotlights a landmark the answer referred to, by its number.
    var point: (Int) -> Void = { _ in }
    /// Flips Attach Picture for questions about the whole window.
    var toggleWindowPicture: () -> Void = {}
    /// Stops the answer being generated and keeps what has arrived.
    var stop: () -> Void = {}
    var saveClaudeKey: (String) -> Void = { _ in }
    var answerOnDevice: () -> Void = {}
    var openSettings: () -> Void = {}
    var dismiss: () -> Void = {}
}
