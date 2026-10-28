import Foundation

/// One thing Robi proposes to do in the app. Nothing runs until the person clicks Run.
///
/// A step names its target the way the person sees it: a menu path, or a window element's number
/// and the label it had when the window was read. `RobiStepRunner` checks that label again before
/// it acts, so a step never lands on a different element than the one shown.
nonisolated enum RobiStep: Equatable, Sendable {
    /// Chooses a menu-bar command, such as "File > New Tab".
    case menu(path: String)
    /// Presses a button or link, or selects an option, in the window.
    case press(element: Int, label: String)
    /// Turns a checkbox or switch on or off. One already in that state counts as done.
    case toggle(element: Int, label: String, on: Bool)
    /// Replaces the text of a field or text area.
    case type(element: Int, label: String, text: String)

    /// The window element the step acts on; nil for a menu command.
    var element: Int? {
        switch self {
        case .menu: nil
        case let .press(element, _), let .toggle(element, _, _), let .type(element, _, _): element
        }
    }
}

/// The steps the model proposed for one answer, in the order they run. One click runs them all.
nonisolated struct RobiProposal: Equatable, Sendable {
    /// The longest chain one click runs.
    static let maximumSteps = 3

    var steps: [RobiStep]

    init(steps: [RobiStep]) {
        self.steps = Array(steps.prefix(Self.maximumSteps))
    }

    var isFull: Bool { steps.count >= Self.maximumSteps }
}

/// How far running a proposal got, for the card.
nonisolated enum RobiRunState: Equatable, Sendable {
    /// Step `index` is running; the ones before it are done.
    case running(index: Int)
    /// Every step ran.
    case done
    /// Step `index` could not run; the ones before it are done and the rest were skipped.
    case failed(index: Int)
}
