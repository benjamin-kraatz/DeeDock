import Foundation

/// What one visit to the Hub's Apps tab did, reduced to counts for `launcher_closed`.
///
/// A visit runs from ``LauncherState/begin(pins:foregroundID:)`` to ``LauncherState/end(_:)``.
/// It holds no app, query, or path: only which kinds of action happened and how often.
nonisolated struct LauncherVisit: Equatable, Sendable {
    /// A deliberate action in the tab. Hover, selection, typing, and scrolling are not actions.
    ///
    /// Cases are ordered by strength: when a visit holds several, the first in this list decides
    /// the outcome.
    nonisolated enum Action: Int, Comparable, CaseIterable, Sendable {
        case launched, openedResult, fileAction, tool, revealed, managed, feedback, robi

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        var outcome: AnalyticsLauncherOutcome {
            switch self {
            case .launched: .launched
            case .openedResult: .openedResult
            case .fileAction: .fileAction
            case .tool: .tool
            case .revealed: .revealed
            case .managed: .managed
            case .feedback: .feedback
            case .robi: .robi
            }
        }
    }

    /// How the tab was left.
    nonisolated enum Exit: Sendable {
        /// Another Hub tab was selected.
        case switchedTab
        /// The Hub closed, after an action or not.
        case closed
    }

    /// Results count as scrolled once their content moved this far, in points, from the top.
    /// A small margin keeps rubber-band and rounding noise out.
    static let scrollThreshold: CGFloat = 4

    /// Actions recorded so far.
    private(set) var actionCount = 0
    /// Browse options chosen so far (`launcher_option_changed`).
    private(set) var optionCount = 0
    /// Whether the grid, list, or search results were away from the top at any point.
    private(set) var scrolled = false
    /// The strongest action recorded, nil before the first.
    private(set) var strongest: Action?

    mutating func record(_ action: Action) {
        actionCount += 1
        strongest = min(strongest ?? action, action)
    }

    mutating func recordOptionChange() { optionCount += 1 }

    mutating func recordScrolled() { scrolled = true }

    /// The visit's outcome: its strongest action, else how the tab was left.
    func outcome(_ exit: Exit) -> AnalyticsLauncherOutcome {
        if let strongest { return strongest.outcome }
        return exit == .switchedTab ? .switchedTab : .none
    }
}
