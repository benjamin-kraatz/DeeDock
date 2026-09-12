import Foundation
import Observation
import Testing
@testable import DeeDock

@MainActor
struct PinJuryTests {
    @Test("A replacement vote writes once, only after explicit Accept")
    func explicitAccept() async {
        let fixture = PinJuryFixture(), generator = ControlledPinJuryGenerator()
        let state = fixture.state(generator: generator)
        defer { state.clear() }
        state.reload()
        state.accept()
        #expect(fixture.writeAttempts == 0)
        state.start()
        await generator.waitUntilStarted()
        await generator.emit(hearing(vote: .replace))
        #expect(!state.canAccept)
        #expect(fixture.writeAttempts == 0)
        await finish(generator, state: state)
        #expect(state.canAccept)
        #expect(fixture.savedIDs == ["before", "incumbent", "after"])
        state.accept()
        state.accept()
        #expect(state.phase == .accepted)
        #expect(fixture.writeAttempts == 1)
        #expect(fixture.savedIDs == ["before", "challenger", "after"])
    }

    @Test("Reject settles a replacement recommendation without a pin write")
    func rejectDoesNotWrite() async {
        let fixture = PinJuryFixture(), generator = ControlledPinJuryGenerator()
        let state = fixture.state(generator: generator)
        defer { state.clear() }
        await deliberate(state, using: generator, vote: .replace)
        state.reject()
        state.accept()
        #expect(state.phase == .rejected)
        #expect(fixture.writeAttempts == 0)
        #expect(fixture.savedIDs.contains("incumbent"))
    }

    @Test("Accepting a keep majority settles the hearing without saving pins")
    func acceptKeepDoesNotWrite() async {
        let fixture = PinJuryFixture(), generator = ControlledPinJuryGenerator()
        let state = fixture.state(generator: generator)
        defer { state.clear() }
        await deliberate(state, using: generator, vote: .keep)
        state.accept()
        #expect(state.phase == .accepted)
        #expect(fixture.writeAttempts == 0)
    }

    @Test("A failed pin write stays reviewable and requires another explicit Accept")
    func failedWriteCanRetry() async {
        let fixture = PinJuryFixture(), generator = ControlledPinJuryGenerator()
        fixture.writeSucceeds = false
        let state = fixture.state(generator: generator)
        defer { state.clear() }
        await deliberate(state, using: generator, vote: .replace)
        state.accept()
        #expect(state.phase == .awaitingDecision)
        #expect(state.message != nil)
        #expect(fixture.writeAttempts == 1)
        #expect(fixture.savedIDs == ["before", "incumbent", "after"])
        fixture.writeSucceeds = true
        #expect(fixture.writeAttempts == 1)
        state.accept()
        #expect(state.phase == .accepted)
        #expect(fixture.writeAttempts == 2)
        #expect(fixture.savedIDs == ["before", "challenger", "after"])
    }

    @Test("An external pin edit invalidates the approved snapshot before any write")
    func stalePinsCannotApply() async {
        let fixture = PinJuryFixture(), generator = ControlledPinJuryGenerator()
        let state = fixture.state(generator: generator)
        defer { state.clear() }
        await deliberate(state, using: generator, vote: .replace)
        fixture.savedIDs = ["external", "incumbent", "after"]
        state.accept()
        #expect(state.phase == .unavailable)
        #expect(state.currentCase == nil)
        #expect(state.turns.isEmpty)
        #expect(fixture.writeAttempts == 0)
        #expect(fixture.savedIDs == ["external", "incumbent", "after"])
    }

    @Test("Incomplete or malformed hearings never enable Accept", arguments: InvalidHearing.allCases)
    func invalidBallots(_ invalid: InvalidHearing) async {
        let fixture = PinJuryFixture(), generator = ControlledPinJuryGenerator()
        let state = fixture.state(generator: generator)
        defer { state.clear() }
        state.reload(); state.start()
        await generator.waitUntilStarted()
        var turns = hearing(vote: .replace)
        switch invalid {
        case .missingTurn:
            turns.removeLast()
        case .partialBallot:
            turns[5] = turn(.steward, round: 2, vote: .replace, complete: false)
        case .missingBallot:
            turns[5] = turn(.steward, round: 2, vote: nil)
        case .duplicateOpening:
            turns[1] = PinJuryTurn(id: "unexpected-opening", juror: .keeper, round: 1,
                                  text: "Duplicate keeper.", vote: .replace, isComplete: true)
        case .wrongRound:
            turns[0] = turn(.keeper, round: 3, vote: .replace)
        case .emptyStatement:
            turns[0] = PinJuryTurn(id: "keeper-1", juror: .keeper, round: 1,
                                  text: "  ", vote: .replace, isComplete: true)
        }
        await generator.emit(turns)
        #expect(!state.canAccept)
        await finish(generator, state: state)
        state.accept()
        #expect(state.phase == .ready)
        #expect(!state.canAccept)
        #expect(fixture.writeAttempts == 0)
    }

    @Test("Generation failure after six apparent ballots still blocks Accept")
    func generationFailureRetiresVerdict() async {
        let fixture = PinJuryFixture(), generator = ControlledPinJuryGenerator()
        let state = fixture.state(generator: generator)
        defer { state.clear() }
        state.reload(); state.start()
        await generator.waitUntilStarted()
        await generator.emit(hearing(vote: .replace))
        await generator.finish(error: .failed)
        await waitUntilSettled(state)
        state.accept()
        #expect(state.phase == .ready)
        #expect(!state.canAccept)
        #expect(fixture.writeAttempts == 0)
    }

    @Test("Cancel preserves received text and ignores late generation callbacks")
    func cancelIgnoresLateTurns() async {
        let fixture = PinJuryFixture(), generator = ControlledPinJuryGenerator()
        let state = fixture.state(generator: generator)
        defer { state.clear() }
        state.reload(); state.start()
        await generator.waitUntilStarted()
        await generator.emit([turn(.keeper, round: 1, vote: nil, complete: false)])
        let received = state.turns
        state.cancel()
        await generator.waitUntilCancelled()
        await generator.emit(hearing(vote: .replace))
        await generator.finish()
        #expect(state.phase == .ready)
        #expect(state.turns == received)
        #expect(!state.canAccept)
        #expect(fixture.writeAttempts == 0)
    }

    @Test("Privacy changes erase the hearing and cancel inference", arguments: PrivacyChange.allCases)
    func privacyChangeIgnoresLateTurns(_ change: PrivacyChange) async {
        let fixture = PinJuryFixture(), generator = ControlledPinJuryGenerator()
        let state = fixture.state(generator: generator)
        defer { state.clear() }
        state.reload(); state.start()
        await generator.waitUntilStarted()
        await generator.emit([turn(.keeper, round: 1, vote: .keep)])
        switch change {
        case .reset: fixture.suggestions.reset()
        case .pause: fixture.suggestions.setPaused(true)
        case .disable: fixture.suggestions.setEnabled(false)
        case .excludeThenInclude:
            // There is deliberately no suspension between these operations. A deferred
            // Observation callback must not see the restored set as restored consent.
            fixture.suggestions.exclude(appID: "challenger")
            fixture.suggestions.include(appID: "challenger")
        }
        await generator.emit(hearing(vote: .replace))
        await generator.waitUntilCancelled()
        await generator.finish()
        state.accept()
        #expect(state.phase == .unavailable)
        #expect(state.currentCase == nil)
        #expect(state.turns.isEmpty)
        #expect(fixture.writeAttempts == 0)
        await fixture.suggestions.flush()
    }

    @Test("Closing clears evidence and late callbacks cannot reopen it")
    func clearIgnoresLateTurns() async {
        let fixture = PinJuryFixture(), generator = ControlledPinJuryGenerator()
        let state = fixture.state(generator: generator)
        state.reload(); state.start()
        await generator.waitUntilStarted()
        state.clear()
        await generator.waitUntilCancelled()
        await generator.emit(hearing(vote: .replace))
        await generator.finish()
        #expect(state.currentCase == nil)
        #expect(state.turns.isEmpty)
        #expect(!state.canStart)
        #expect(!state.canAccept)
        #expect(fixture.writeAttempts == 0)
    }

    @Test("Expired and future-dated cases cannot start", arguments: [-901.0, 60.0])
    func invalidCaseAge(_ offset: TimeInterval) {
        let fixture = PinJuryFixture()
        let state = fixture.state(generator: ControlledPinJuryGenerator(), date: Date().addingTimeInterval(offset))
        defer { state.clear() }
        state.reload(); state.start(); state.accept()
        #expect(state.phase == .unavailable)
        #expect(state.currentCase == nil)
        #expect(fixture.writeAttempts == 0)
    }

    @Test("Policy requires all challenger evidence gates", arguments: [
        PinJuryEvidence(activations: 5, recentActivations: 3, activeDays: 3, daysSinceUse: 0),
        PinJuryEvidence(activations: 6, recentActivations: 2, activeDays: 3, daysSinceUse: 0),
        PinJuryEvidence(activations: 6, recentActivations: 3, activeDays: 2, daysSinceUse: 0)
    ])
    func policyEvidenceGates(_ evidence: PinJuryEvidence) {
        #expect(PinJuryPolicy.makeCase(pins: [app("incumbent")], challengers: [app("challenger")],
            evidence: ["incumbent": usage(1), "challenger": evidence]) == nil)
    }

    @Test("Unknown pins and Finder are protected despite a strong challenger")
    func policyProtectsUnknownPins() {
        let evidence = ["challenger": usage(20), "com.apple.finder": usage(1)]
        #expect(PinJuryPolicy.makeCase(pins: [app("unknown"), app("com.apple.finder")],
            challengers: [app("challenger")], evidence: evidence) == nil)
    }

    @Test("Policy ties use stable IDs and a challenger cannot already be pinned")
    func policyStableSelection() throws {
        let evidence = ["pin.a": usage(1), "pin.b": usage(1), "new.a": usage(10), "new.b": usage(10)]
        let first = try #require(PinJuryPolicy.makeCase(pins: [app("pin.b"), app("pin.a")],
            challengers: [app("new.b"), app("pin.a"), app("new.a")], evidence: evidence))
        let second = try #require(PinJuryPolicy.makeCase(pins: [app("pin.a"), app("pin.b")],
            challengers: [app("new.a"), app("new.b")], evidence: evidence))
        #expect(first.incumbent.id == "pin.a")
        #expect(first.challenger.id == "new.a")
        #expect(first.incumbent == second.incumbent)
        #expect(first.challenger == second.challenger)
        #expect(PinJuryPolicy.makeCase(pins: [app("new.a")], challengers: [app("new.a")], evidence: evidence) == nil)
    }

    @Test("Score advantage can be tuned without a model or persistence")
    func policyTunableMargin() {
        let evidence = ["incumbent": usage(5), "challenger": usage(6)]
        #expect(PinJuryPolicy.makeCase(pins: [app("incumbent")], challengers: [app("challenger")], evidence: evidence) == nil)
        let tuning = PinJuryTuning(minimumScoreAdvantage: 1)
        #expect(PinJuryPolicy.makeCase(pins: [app("incumbent")], challengers: [app("challenger")],
                                     evidence: evidence, tuning: tuning) != nil)
        #expect(PinJuryPolicy.score(PinJuryEvidence(activations: .max, recentActivations: .max,
            activeDays: .max, daysSinceUse: nil)) == PinJuryPolicy.maximumScore)
    }

    private func deliberate(_ state: PinJuryState, using generator: ControlledPinJuryGenerator, vote: PinJuryVote) async {
        state.reload(); state.start()
        await generator.waitUntilStarted()
        await generator.emit(hearing(vote: vote))
        await finish(generator, state: state)
    }

    private func finish(_ generator: ControlledPinJuryGenerator, state: PinJuryState) async {
        await generator.finish()
        await waitUntilSettled(state)
    }

    private func waitUntilSettled(_ state: PinJuryState) async {
        await withCheckedContinuation { resumeWhenSettled(state, continuation: $0) }
    }

    private func resumeWhenSettled(_ state: PinJuryState, continuation: CheckedContinuation<Void, Never>) {
        guard state.isBusy else { continuation.resume(); return }
        withObservationTracking { _ = state.isBusy } onChange: {
            Task { @MainActor in resumeWhenSettled(state, continuation: continuation) }
        }
    }

    private func hearing(vote: PinJuryVote) -> [PinJuryTurn] {
        (1...2).flatMap { round in PinJuror.allCases.map { turn($0, round: round, vote: vote) } }
    }

    private func turn(_ juror: PinJuror, round: Int, vote: PinJuryVote?, complete: Bool = true) -> PinJuryTurn {
        PinJuryTurn(id: "\(juror.rawValue)-\(round)", juror: juror, round: round,
                    text: "The supplied observations support this ballot.", vote: vote, isComplete: complete)
    }

    private func app(_ id: String) -> ApplicationReference { PinJuryFixture.app(id) }

    private func usage(_ activations: Int) -> PinJuryEvidence {
        PinJuryEvidence(activations: activations, recentActivations: min(3, activations),
                        activeDays: min(3, activations), daysSinceUse: 1)
    }

    nonisolated enum InvalidHearing: CaseIterable, Sendable {
        case missingTurn, partialBallot, missingBallot, duplicateOpening, wrongRound, emptyStatement
    }
    nonisolated enum PrivacyChange: CaseIterable, Sendable { case reset, pause, disable, excludeThenInclude }
}

/// Pin storage is an in-memory ordered list. Its mutation is observed like the real mode projection.
@MainActor @Observable
private final class PinJuryFixture {
    let suggestions = LauncherSuggestionsStore(directory: nil, defaults: nil)
    var savedIDs = ["before", "incumbent", "after"]
    var writeSucceeds = true
    var writeAttempts = 0

    init() { suggestions.setEnabled(true) }

    func state(generator: any PinJuryGenerating, date: Date = Date()) -> PinJuryState {
        PinJuryState(displayName: "Test display", generator: generator) { [self] in
            let pins = savedIDs, revision = suggestions.revision, privacy = suggestions.pinJuryPrivacyRevision
            let evidence = PinJuryEvidence(activations: 6, recentActivations: 3, activeDays: 3, daysSinceUse: 1)
            let hearing = PinJuryCase(incumbent: .init(application: Self.app("incumbent"), evidence: evidence),
                challenger: .init(application: Self.app("challenger"), evidence: evidence), createdAt: date)
            return .ready(PinJuryReview(evidence: hearing,
                privacyIsValid: { [self] in suggestions.isActive && suggestions.revision == revision
                    && suggestions.pinJuryPrivacyRevision == privacy },
                isValid: { [self] in savedIDs == pins },
                apply: { [self] in
                    writeAttempts += 1
                    guard writeSucceeds, savedIDs == pins else { return false }
                    savedIDs = ["before", "challenger", "after"]
                    return true
                }))
        }
    }

    static func app(_ id: String) -> ApplicationReference {
        ApplicationReference(bundleIdentifier: id, url: URL(fileURLWithPath: "/Applications/\(id).app"), name: id)
    }
}

/// Deliberately retains its callback after cancellation to exercise the state's late-result guard.
private actor ControlledPinJuryGenerator: PinJuryGenerating {
    private var update: (@Sendable (PinJuryTurn) async -> Void)?
    private var completion: CheckedContinuation<Void, Error>?
    private var started: [CheckedContinuation<Void, Never>] = []
    private var cancelled: [CheckedContinuation<Void, Never>] = []
    private var sawCancellation = false

    func deliberate(_ juryCase: PinJuryCase, localeIdentifier: String,
                    update: @escaping @Sendable (PinJuryTurn) async -> Void) async throws {
        self.update = update
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                completion = continuation
                started.forEach { $0.resume() }; started.removeAll()
            }
        } onCancel: {
            Task { await self.noteCancellation() }
        }
    }

    func waitUntilStarted() async {
        if completion == nil { await withCheckedContinuation { started.append($0) } }
    }

    func waitUntilCancelled() async {
        if !sawCancellation { await withCheckedContinuation { cancelled.append($0) } }
    }

    func emit(_ turns: [PinJuryTurn]) async {
        for turn in turns { await update?(turn) }
    }

    func finish(error: PinJuryFailure? = nil) {
        guard let completion else { return }
        self.completion = nil
        if let error { completion.resume(throwing: error) }
        else { completion.resume() }
    }

    private func noteCancellation() {
        sawCancellation = true
        cancelled.forEach { $0.resume() }; cancelled.removeAll()
    }
}
