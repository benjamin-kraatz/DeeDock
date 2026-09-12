import Foundation
import Observation

enum PinJuryPhase { case ready, generating, awaitingDecision, accepted, rejected, unavailable }

/// Captures one display and mode. Both validation and the single pin write run synchronously
/// on MainActor, so another pin edit cannot interleave with Accept.
struct PinJuryReview {
    let evidence: PinJuryCase
    let privacyIsValid: () -> Bool
    let isValid: () -> Bool
    let apply: () -> Bool
}

enum PinJuryPreparation {
    case ready(PinJuryReview)
    case unavailable(LocalizedStringResource, needsHistory: Bool = false)
}

/// Owns a single ephemeral hearing. Partial text and partial ballots can never enable Accept.
@MainActor @Observable
final class PinJuryState {
    private(set) var currentCase: PinJuryCase?
    private(set) var turns: [PinJuryTurn] = []
    private(set) var phase: PinJuryPhase = .ready
    private(set) var message: LocalizedStringResource?
    let displayName: String
    private(set) var needsHistory = false
    @ObservationIgnored private let prepare: () -> PinJuryPreparation
    @ObservationIgnored private let generator: any PinJuryGenerating
    @ObservationIgnored private var review: PinJuryReview?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var deadline: Task<Void, Never>?
    @ObservationIgnored private var expiry: Task<Void, Never>?
    @ObservationIgnored private var attempt = UUID()
    @ObservationIgnored private var observation = UUID()

    var isBusy: Bool { phase == .generating }
    var canStart: Bool { currentCase != nil && !isBusy && phase != .awaitingDecision && phase != .accepted && phase != .rejected }
    var canAccept: Bool { phase == .awaitingDecision && finalVote != nil }
    var finalVote: PinJuryVote? {
        let expected = Set((1...2).flatMap { round in PinJuror.allCases.map { "\($0.rawValue)-\(round)" } })
        guard turns.count == 6, Set(turns.map(\.id)) == expected,
              turns.allSatisfy({ turn in
                  (1...2).contains(turn.round) && turn.id == "\(turn.juror.rawValue)-\(turn.round)"
                      && turn.isComplete && turn.vote != nil && turn.text.count <= 1_200
                      && !turn.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }) else { return nil }
        let ballots = turns.filter { $0.round == 2 && $0.isComplete }
        guard ballots.count == 3, Set(ballots.map(\.juror)).count == 3,
              ballots.allSatisfy({ $0.vote != nil }), turns.count == 6,
              turns.allSatisfy(\.isComplete) else { return nil }
        return ballots.filter { $0.vote == .replace }.count >= 2 ? .replace : .keep
    }

    init(displayName: String, generator: any PinJuryGenerating = FoundationModelsPinJury(),
         prepare: @escaping () -> PinJuryPreparation) {
        self.displayName = displayName
        self.generator = generator
        self.prepare = prepare
    }

    func reload() {
        clear()
        switch prepare() {
        case .ready(let review):
            self.review = review
            currentCase = review.evidence
            phase = .ready
            watchValidity()
            let observation = observation
            expiry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15 * 60))
                guard !Task.isCancelled, let self, self.observation == observation else { return }
                invalidate()
            }
        case .unavailable(let message, let needsHistory):
            phase = .unavailable
            self.message = message
            self.needsHistory = needsHistory
        }
    }

    func start() {
        guard canStart, let currentCase, validate() else { return }
        let previous = task
        cancel()
        let id = UUID()
        attempt = id
        turns = []
        message = nil
        phase = .generating
        let generator = generator
        let locale = Locale.current.identifier
        task = Task { [weak self] in
            // A cancelled Foundation Models stream must unwind before a retry begins.
            await previous?.value
            guard !Task.isCancelled, let self, attempt == id else { return }
            do {
                try await generator.deliberate(currentCase, localeIdentifier: locale) { [weak self] turn in
                    await self?.receive(turn, attempt: id)
                }
                try Task.checkCancellation()
                guard attempt == id, validate() else { return }
                guard finalVote != nil else { throw PinJuryFailure.invalidOutput }
                phase = .awaitingDecision
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled, attempt == id else { return }
                message = Self.message(for: error)
                phase = .ready
            }
            guard attempt == id else { return }
            deadline?.cancel(); deadline = nil
            task = nil
        }
        deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(180))
            guard !Task.isCancelled, let self, attempt == id else { return }
            cancel()
            message = .pinJuryTimeout
        }
    }

    private func receive(_ turn: PinJuryTurn, attempt id: UUID) {
        guard attempt == id, isBusy, validate() else { return }
        if let index = turns.firstIndex(where: { $0.id == turn.id }) { turns[index] = turn }
        else { turns.append(turn) }
    }

    /// Stops inference without inventing a verdict. Completed statements remain reviewable.
    func cancel() {
        attempt = UUID()
        task?.cancel()
        deadline?.cancel(); deadline = nil
        if isBusy { phase = .ready; message = .pinJuryCancelled }
    }

    func reject() {
        guard phase == .awaitingDecision else { return }
        phase = .rejected
        message = .pinJuryRejected
    }

    func accept() {
        guard canAccept, validate(), let review, let finalVote else { return }
        // Persistence publishes synchronously and triggers Observation. Settle first so that
        // our own successful swap is not mistaken for an external stale-snapshot edit.
        phase = .accepted
        if finalVote == .keep { message = .pinJuryKept; return }
        guard review.apply() else {
            phase = .awaitingDecision
            message = .pinJurySaveFailed
            return
        }
        message = .pinJuryApplied
    }

    /// Closing, locking, or removing a display discards all transcript and evidence data.
    func clear() {
        cancel()
        observation = UUID()
        expiry?.cancel(); expiry = nil
        currentCase = nil; review = nil; turns = []; message = nil
        needsHistory = false; phase = .ready
    }

    private func validate() -> Bool {
        guard let review, review.privacyIsValid(), review.isValid(),
              Date().timeIntervalSince(review.evidence.createdAt) < 15 * 60,
              Date() >= review.evidence.createdAt else {
            invalidate()
            return false
        }
        return true
    }

    private func invalidate() {
        clear()
        phase = .unavailable
        message = .pinJuryStale
    }

    private func watchValidity() {
        guard let review else { return }
        let id = observation
        let valid = withObservationTracking {
            review.privacyIsValid() && ((phase == .accepted || phase == .rejected) || review.isValid())
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, observation == id else { return }
                watchValidity()
            }
        }
        if !valid { invalidate() }
    }

    private static func message(for error: Error) -> LocalizedStringResource {
        switch error as? PinJuryFailure {
        case .deviceNotEligible: .pinJuryDeviceNotEligible
        case .intelligenceDisabled: .pinJuryIntelligenceDisabled
        case .modelNotReady: .pinJuryModelNotReady
        case .unsupported: .pinJuryUnsupported
        case .contextLimit: .pinJuryContextLimit
        case .refused: .pinJuryRefused
        default: .pinJuryGenerationFailed
        }
    }
}

#if DEBUG
extension PinJuryState {
    /// Inert canvas fixtures never acquire the app catalog, read preferences or run a model.
    static func preview(phase: PinJuryPhase = .awaitingDecision) -> PinJuryState {
        let state = PinJuryState(displayName: "Studio Display", prepare: { .unavailable(.pinJuryHistoryRequired) })
        state.phase = phase
        if phase == .unavailable {
            state.message = .pinJuryHistoryRequired
            state.needsHistory = true
            return state
        }
        state.currentCase = PinJuryCase(
            incumbent: PinJuryCandidate(application: .init(bundleIdentifier: "preview.safari",
                url: URL(fileURLWithPath: "/Preview/Safari.app"), name: "Safari"),
                evidence: .init(activations: 8, recentActivations: 2, activeDays: 4, daysSinceUse: 3)),
            challenger: PinJuryCandidate(application: .init(bundleIdentifier: "preview.notes",
                url: URL(fileURLWithPath: "/Preview/Notes.app"), name: "Notes"),
                evidence: .init(activations: 34, recentActivations: 18, activeDays: 12, daysSinceUse: 0)),
            createdAt: Date(timeIntervalSince1970: 1_789_200_000))
        state.turns = (1...2).flatMap { round in
            PinJuror.allCases.map { juror in
                PinJuryTurn(id: "\(juror.rawValue)-\(round)", juror: juror, round: round,
                    text: String(localized: juror == .keeper ? .pinJuryPreviewKeeper : .pinJuryPreviewChallenger),
                    vote: juror == .keeper ? .keep : .replace, isComplete: true)
            }
        }
        if phase == .generating {
            state.turns = Array(state.turns.prefix(3)) + [PinJuryTurn(id: "keeper-2", juror: .keeper,
                round: 2, text: String(localized: .pinJuryPreviewKeeper), vote: nil, isComplete: false)]
        }
        return state
    }
}
#endif
