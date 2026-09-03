import Testing
import Foundation
@testable import DeeDock

/// Navigation has to reach every page and stop at both ends; a tour that can skip a page or run
/// off the end is a first impression nobody gets to retake.
@Suite("Onboarding navigation")
@MainActor
struct OnboardingNavigationTests {
    private func store() -> OnboardingStore {
        OnboardingStore(repository: OnboardingRepository(defaults: scratchDefaults()))
    }

    @Test("The tour starts at the first page")
    func startsAtWelcome() {
        let store = store()
        #expect(store.step == .welcome)
        #expect(!store.canGoBack)
        #expect(!store.isFinalStep)
    }

    @Test("Advancing visits every page in order and then reports the end")
    func visitsEveryStep() {
        let store = store()
        var visited: [OnboardingStep] = [store.step]
        while !store.advance() { visited.append(store.step) }
        #expect(visited == OnboardingStep.allCases)
        // The call that finished the tour left the final page on screen.
        #expect(store.step == OnboardingStep.allCases.last)
    }

    @Test("Back stops at the first page instead of running off the start")
    func backClampsAtStart() {
        let store = store()
        store.goBack()
        #expect(store.step == .welcome)
        _ = store.advance()
        store.goBack()
        #expect(store.step == .welcome)
    }

    @Test("Only the macOS Dock guide can be skipped")
    func skipAppliesToTheGuideAlone() {
        #expect(OnboardingStep.allCases.filter(\.isSkippable) == [.systemDock])

        let store = store()
        store.skip()
        #expect(store.step == .welcome, "Skip must do nothing on a page that is not skippable")

        _ = store.advance()
        #expect(store.step == .systemDock)
        store.skip()
        #expect(store.step == OnboardingStep.systemDock.next)
    }

    @Test("Direction follows the last move, so pages leave the way they came")
    func tracksDirection() {
        let store = store()
        _ = store.advance()
        #expect(store.isMovingForward)
        store.goBack()
        #expect(!store.isMovingForward)
        store.restart()
        #expect(store.isMovingForward)
        #expect(store.step == .welcome)
    }

    @Test("Steps report their own position and neighbours")
    func stepOrdering() {
        #expect(OnboardingStep.welcome.previous == nil)
        #expect(OnboardingStep.welcome.index == 0)
        #expect(OnboardingStep.allCases.last?.next == nil)
        for step in OnboardingStep.allCases {
            #expect(step.next?.previous == step || step.next == nil)
            #expect(step.index == OnboardingStep.allCases.firstIndex(of: step))
        }
    }
}

/// Onboarding must appear exactly once. Showing it twice is annoying; never showing it wastes
/// the only moment a person is willing to read an introduction.
@Suite("Onboarding persistence")
@MainActor
struct OnboardingPersistenceTests {
    private let key = "onboarding.v1"

    @Test("A first launch presents the tour")
    func firstLaunchPresents() {
        let repository = OnboardingRepository(defaults: scratchDefaults())
        #expect(repository.needsOnboarding())
        #expect(repository.load() == nil)
    }

    @Test("Completing the tour stops it coming back")
    func completionPersists() {
        let defaults = scratchDefaults()
        let repository = OnboardingRepository(defaults: defaults)
        repository.complete()
        #expect(!repository.needsOnboarding())
        #expect(repository.load() == OnboardingRecord(completedVersion: OnboardingRepository.currentVersion))
        // A second repository over the same preferences agrees, as a later launch would.
        #expect(!OnboardingRepository(defaults: defaults).needsOnboarding())
    }

    @Test("Dismissing through the store records the same thing as finishing")
    func storeRecordsCompletion() {
        let defaults = scratchDefaults()
        let store = OnboardingStore(repository: OnboardingRepository(defaults: defaults))
        #expect(store.shouldPresentAutomatically)
        store.complete()
        #expect(!store.shouldPresentAutomatically)
    }

    @Test("An older completed version is offered the tour again")
    func olderVersionPresents() throws {
        let defaults = scratchDefaults()
        let stale = try JSONEncoder().encode(OnboardingRecord(completedVersion: OnboardingRepository.currentVersion - 1))
        defaults.set(stale, forKey: key)
        #expect(OnboardingRepository(defaults: defaults).needsOnboarding())
    }

    @Test("Unreadable data is treated as seen rather than shown every launch")
    func unreadableRecordStaysQuiet() {
        let defaults = scratchDefaults()
        defaults.set(Data("not a record".utf8), forKey: key)
        let repository = OnboardingRepository(defaults: defaults)
        #expect(!repository.needsOnboarding())
        // Reading must not repair or replace the stored bytes.
        #expect(defaults.data(forKey: key) == Data("not a record".utf8))
    }

    @Test("A value of the wrong type is treated the same way")
    func wrongTypeStaysQuiet() {
        let defaults = scratchDefaults()
        defaults.set("a string", forKey: key)
        #expect(!OnboardingRepository(defaults: defaults).needsOnboarding())
    }
}

/// Each test gets its own preferences so completion in one never suppresses the tour in another.
@MainActor
private func scratchDefaults() -> UserDefaults {
    let suite = "onboarding.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}
