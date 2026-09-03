import Foundation
import Observation

/// Navigation state for one run of the tour, plus the record of having seen it.
///
/// Completion is recorded when a person reaches the end *or* dismisses the window: closing the
/// tour is a decision, and re-presenting it on the next launch would be nagging. Reopening the
/// tour from the menu bar therefore never changes what is stored.
@MainActor @Observable
final class OnboardingStore {
    private(set) var step: OnboardingStep = .welcome
    /// Direction of the most recent move, so the shell can send content out the way it came.
    private(set) var isMovingForward = true

    @ObservationIgnored private let repository: OnboardingRepository

    /// A repository over a scratch `UserDefaults` gives previews and tests isolated state.
    /// The default is built here rather than in the parameter list, where a main-actor value
    /// would be constructed in a nonisolated context.
    init(repository: OnboardingRepository? = nil) {
        self.repository = repository ?? OnboardingRepository()
    }

    /// True on a launch where the tour has not yet been completed or dismissed.
    var shouldPresentAutomatically: Bool { repository.needsOnboarding() }

    var canGoBack: Bool { step.previous != nil }
    var isFinalStep: Bool { step.next == nil }
    var totalSteps: Int { OnboardingStep.allCases.count }

    /// Moves to the next step, or reports that the tour is over so the owner can close the window.
    /// - Returns: true when the tour is finished.
    @discardableResult
    func advance() -> Bool {
        guard let next = step.next else {
            complete()
            return true
        }
        isMovingForward = true
        step = next
        return false
    }

    func goBack() {
        guard let previous = step.previous else { return }
        isMovingForward = false
        step = previous
    }

    /// Passes over a skippable step without treating it as a dismissal of the whole tour.
    func skip() {
        guard step.isSkippable else { return }
        advance()
    }

    /// Restarts the tour for a person who reopened it from the menu.
    func restart() {
        isMovingForward = true
        step = .welcome
    }

    /// Records that the tour has been seen. Safe to call more than once.
    func complete() { repository.complete() }
}
