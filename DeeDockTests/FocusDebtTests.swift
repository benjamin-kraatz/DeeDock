import Foundation
import Testing
@testable import DeeDock

@Suite("Opt-in focus debt")
struct FocusDebtTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(phase: FocusSession.Phase = .running) -> FocusSession {
        FocusSession(id: UUID(), modeID: UUID(), modeName: "Writing", duration: 1500,
                     remainingWhenPaused: phase == .completed ? 0 : 900,
                     deadline: phase == .running ? now.addingTimeInterval(900) : nil, phase: phase)
    }

    @Test("Older saved timers keep the meter off")
    func migration() throws {
        let data = Data(#"{"version":1,"minutes":25,"celebrates":false}"#.utf8)
        let saved = try JSONDecoder().decode(FocusSessionsDocument.self, from: data)
        let debt = saved.focusDebt ?? FocusDebtState()
        #expect(!debt.enabled)
        #expect(debt.count == 0)
    }

    @Test("An early end consumes a promise only once", arguments: [FocusSession.Phase.running, .paused])
    func earlyEnd(phase: FocusSession.Phase) {
        let timer = session(phase: phase)
        var debt = FocusDebtState()
        debt.configure(enabled: true)
        debt.begin(sessionID: timer.id)
        debt.end(timer, at: now)
        debt.end(timer, at: now)
        #expect(debt.count == 1)
        #expect(debt.promisedSessionID == nil)
    }

    @Test("A deadline reached during sleep or downtime adds no debt", arguments: [900.0, 1800.0])
    func naturalEnd(elapsed: TimeInterval) {
        let timer = session()
        var debt = FocusDebtState()
        debt.configure(enabled: true)
        debt.begin(sessionID: timer.id)
        debt.end(timer, at: now.addingTimeInterval(elapsed))
        #expect(debt.count == 0)
        #expect(debt.promisedSessionID == nil)
    }

    @Test("Opting in during a session never makes a retroactive promise")
    func optInMidSession() {
        let timer = session()
        var debt = FocusDebtState()
        debt.begin(sessionID: timer.id)
        debt.configure(enabled: true)
        debt.end(timer, at: now)
        #expect(debt.count == 0)
    }

    @Test("Disabling clears debt and does not revive the promise on re-enable")
    func killSwitch() {
        let first = session()
        let second = session()
        var debt = FocusDebtState()
        debt.configure(enabled: true)
        debt.begin(sessionID: first.id)
        debt.end(first, at: now)
        debt.begin(sessionID: second.id)
        debt.configure(enabled: false)
        #expect(debt == FocusDebtState())
        debt.configure(enabled: true)
        debt.end(second, at: now)
        #expect(debt.count == 0)
    }

    @Test("Saved promises survive relaunch without accepting a different session")
    func savedPromise() throws {
        let timer = session()
        var debt = FocusDebtState()
        debt.configure(enabled: true)
        debt.begin(sessionID: timer.id)
        let data = try JSONEncoder().encode(debt)
        var restored = try JSONDecoder().decode(FocusDebtState.self, from: data)
        restored.end(session(), at: now)
        #expect(restored.promisedSessionID == timer.id)
        restored.end(timer, at: now)
        #expect(restored.count == 1)
    }

    @MainActor
    @Test("Finish and cancel persist one increment; completed dismissal adds none", arguments: [false, true])
    func controllerEnd(cancel: Bool) throws {
        let suite = "FocusDebtTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = FocusSessionController(defaults: defaults)
        defer { controller.stop() }
        controller.configureFocusDebt(enabled: true)
        controller.begin(modeID: UUID(), name: "Writing")
        controller.pause()
        #expect(controller.focusDebt.count == 0)
        if cancel { controller.dismiss() }
        else { controller.finish(); controller.dismiss() }
        #expect(controller.focusDebt.count == 1)
        let data = try #require(defaults.data(forKey: "dock.focus-sessions.v1"))
        let saved = try JSONDecoder().decode(FocusSessionsDocument.self, from: data)
        #expect(saved.focusDebt?.count == 1)
        #expect(saved.session == nil)
        #expect(saved.focusDebt?.promisedSessionID == nil)
    }

    @MainActor
    @Test("Kill switch preserves the active timer and persists an empty disabled meter")
    func controllerKill() throws {
        let suite = "FocusDebtTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = FocusSessionController(defaults: defaults)
        defer { controller.stop() }
        controller.configureFocusDebt(enabled: true)
        controller.begin(modeID: UUID(), name: "Writing")
        controller.finish()
        controller.begin(modeID: UUID(), name: "Writing")
        let timer = try #require(controller.session)
        controller.configureFocusDebt(enabled: false)
        #expect(controller.session == timer)
        #expect(controller.focusDebt == FocusDebtState())
        let data = try #require(defaults.data(forKey: "dock.focus-sessions.v1"))
        let saved = try JSONDecoder().decode(FocusSessionsDocument.self, from: data)
        #expect(saved.focusDebt == FocusDebtState())
        #expect(saved.session == timer)
        controller.configureFocusDebt(enabled: true)
        controller.finish()
        #expect(controller.focusDebt.count == 0)
    }
}
