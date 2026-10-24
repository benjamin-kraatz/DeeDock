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
    /// The selection can be replaced in place through Accessibility.
    var canReplace = false
    var answerModel: RobiAnswerModel = .onDevice
    var claudeEffort: RobiClaudeEffort = .medium
    var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    var reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency

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
        if phase == .prompting { height += RobiMetrics.suggestionHeight }
        if phase.showsCard { height += RobiMetrics.cardHeight }
        return CGSize(width: width + 2 * RobiMetrics.sideMargin, height: height)
    }

    /// Clears everything an interaction left behind.
    func resetInteraction() {
        context = nil
        isReadingContext = false
        prompt = ""
        request = ""
        answer = ""
        proposal = nil
        notice = nil
        toast = nil
        canReplace = false
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
}

/// What Robi's views can ask the controller to do.
struct RobiActions {
    var tapFace: () -> Void = {}
    var submit: (String) -> Void = { _ in }
    var suggest: (RobiIntent) -> Void = { _ in }
    var copy: () -> Void = {}
    var replace: () -> Void = {}
    var paste: () -> Void = {}
    var runProposal: () -> Void = {}
    var saveClaudeKey: (String) -> Void = { _ in }
    var answerOnDevice: () -> Void = {}
    var openSettings: () -> Void = {}
    var dismiss: () -> Void = {}
}
