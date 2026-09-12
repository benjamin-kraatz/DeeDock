import Foundation
import Observation
import OSLog

/// App-wide opt-in Sims moods and the light care loop.
///
/// All state stays on this Mac. Rumours use the on-device Foundation Model after separate consent, with no account or network call.
/// Moods are clocks: the store writes care timestamps and the overlay derives the face
/// from elapsed time. Turning the feature off hides overlays without deleting pets.
@MainActor @Observable
final class DockSimsStore {
    private(set) var document = DockSimsDocument.empty
    private(set) var requiresReset = false
    private(set) var storageFailed = false
    @ObservationIgnored private let repository: DockSimsRepository
    @ObservationIgnored private let rumourComposer = FoundationModelsRumourComposer()
    @ObservationIgnored private var rumourConsentGeneration = UUID()
    @ObservationIgnored private var recentRumours: [String] = []
    private(set) var rumourStatus: DockRumourStatus = .ready
    private(set) var lastRumourDiagnostic: DockRumourDiagnostic?
    private static let rumourLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.deedock",
                                             category: "IconRumours")

    #if DEBUG
    /// One pending manual round, claimed by the first eligible display. Never persisted.
    private(set) var debugRumourRoundID: UUID?
    @ObservationIgnored private var claimedDebugRumourRoundID: UUID?
    private var debugRumourRequestsInFlight = 0
    var canTriggerDebugRumour: Bool {
        isEnabled && aiRumoursEnabled && !requiresReset && debugRumourRequestsInFlight == 0
    }

    func triggerDebugRumourRound() {
        guard canTriggerDebugRumour else { return }
        debugRumourRoundID = UUID()
    }

    /// Claiming is deliberately not observable: it must not cancel the task consuming the round.
    func claimDebugRumourRound(_ id: UUID?) -> Bool {
        guard let id, id == debugRumourRoundID, id != claimedDebugRumourRoundID else { return false }
        claimedDebugRumourRoundID = id
        return true
    }
    #endif

    var isEnabled: Bool { document.isEnabled }
    var aiRumoursEnabled: Bool { document.aiRumoursEnabled }
    var intensity: Double { document.intensity }
    var hasPets: Bool { !document.pets.isEmpty }
    /// Session-only care-clock shift. Zero in Release. Not written to `dock.sims.v1`.
    private(set) var debugTimeOffset: TimeInterval = 0

    /// Wall clock plus the debug offset, used when a caller does not pass an explicit instant.
    var currentTime: Date { Date.now.addingTimeInterval(sanitizedOffset) }

    private var sanitizedOffset: TimeInterval {
        debugTimeOffset.isFinite ? debugTimeOffset : 0
    }

    init(repository: DockSimsRepository = DockSimsRepository()) {
        self.repository = repository
    }

    /// Loads stored moods. A missing key leaves the opt-in off.
    func start() {
        do {
            if let stored = try repository.load() {
                document = stored
            }
        } catch {
            requiresReset = true
            storageFailed = true
        }
    }

    func setEnabled(_ enabled: Bool, at date: Date? = nil) {
        guard !requiresReset, document.isEnabled != enabled else { return }
        let instant = date ?? currentTime
        document.isEnabled = enabled
        invalidateRumours()
        if enabled, document.baselineAt == nil {
            document.baselineAt = instant
        }
        persist()
    }

    func setIntensity(_ value: Double) {
        guard !requiresReset else { return }
        let clamped = DockSimsLimits.clampIntensity(value)
        guard document.intensity != clamped else { return }
        document.intensity = clamped
        persist()
    }

    /// Grants consent for on-device AI rumours. Playback also requires Sims and an idle, visible dock.
    func setAIRumoursEnabled(_ enabled: Bool) {
        guard !requiresReset, document.aiRumoursEnabled != enabled else { return }
        document.aiRumoursEnabled = enabled
        invalidateRumours()
        persist()
    }

    /// Called when Settings appears or the app becomes active; generation checks availability again.
    func refreshRumourAvailability(locale: Locale) {
        let availability = FoundationModelsRumourComposer.availability(locale: locale)
        // Opening Settings must not clear the error the person came here to investigate.
        if availability != .ready || lastRumourDiagnostic == nil { rumourStatus = availability }
    }

    /// Model work stays in the composer actor. Consent and cancellation are checked on both sides
    /// of the await so disabling then re-enabling cannot revive an older response.
    func generateRumour(participants: [DockRumourParticipant], locale: Locale) async -> DockRumour? {
        guard isEnabled, aiRumoursEnabled, !requiresReset, !Task.isCancelled else { return nil }
        #if DEBUG
        debugRumourRequestsInFlight += 1
        defer { debugRumourRequestsInFlight -= 1 }
        #endif
        let consent = rumourConsentGeneration
        let requestID = UUID()
        let startedAt = Date.now
        Self.rumourLogger.info("Generation started request=\(requestID.uuidString, privacy: .public) candidates=\(participants.count) locale=\(locale.identifier, privacy: .public)")
        do {
            let result = try await rumourComposer.compose(participants: participants, locale: locale, recent: recentRumours)
            guard !Task.isCancelled, consent == rumourConsentGeneration, isEnabled, aiRumoursEnabled else { return nil }
            rumourStatus = .ready
            lastRumourDiagnostic = nil
            Self.rumourLogger.info("Generation succeeded request=\(requestID.uuidString, privacy: .public) seconds=\(Date.now.timeIntervalSince(startedAt)) openingCharacters=\(result.opening.count) replyCharacters=\(result.reply.count)")
            recentRumours.append(result.opening + " / " + result.reply)
            recentRumours = Array(recentRumours.suffix(3))
            return result
        } catch {
            guard !Task.isCancelled, consent == rumourConsentGeneration else {
                Self.rumourLogger.debug("Generation cancelled request=\(requestID.uuidString, privacy: .public)")
                return nil
            }
            if case FoundationModelsRumourComposer.Failure.busy = error {
                Self.rumourLogger.debug("Generation skipped, composer busy request=\(requestID.uuidString, privacy: .public)")
                return nil
            }
            let diagnostic = DockRumourDiagnostic(error: error, requestID: requestID)
            lastRumourDiagnostic = diagnostic
            Self.rumourLogger.error("\(diagnostic.report, privacy: .public)")
            // Framework descriptions can contain source text. Keep those private in unified logging.
            Self.rumourLogger.debug("Underlying generation failure: \(String(reflecting: error), privacy: .private)")
            if case FoundationModelsRumourComposer.Failure.unavailable(let status) = error {
                rumourStatus = status
            } else if case FoundationModelsRumourComposer.Failure.invalidOutput = error {
                rumourStatus = .invalidOutput
            } else {
                rumourStatus = .generationFailed
            }
            return nil
        }
    }

    private func invalidateRumours() {
        #if DEBUG
        debugRumourRoundID = nil
        claimedDebugRumourRoundID = nil
        #endif
        rumourConsentGeneration = UUID()
        recentRumours = []
        rumourStatus = .ready
        lastRumourDiagnostic = nil
    }

    /// Feed, cheer, or settle one pinned app. Unpinned running tiles are ignored.
    func care(_ action: DockSimsCareAction, pinID: String, at date: Date? = nil) {
        let instant = date ?? currentTime
        guard !requiresReset, document.isEnabled, DockSimsLimits.isValidPinID(pinID),
              instant.timeIntervalSince1970.isFinite else { return }
        let clocks = document.clocks(for: pinID, at: instant) ?? (instant, instant)
        var pet = DockSimsPet(pinID: pinID, lastFedAt: clocks.fed, lastCheeredAt: clocks.cheered)
        switch action {
        case .feed:
            pet.lastFedAt = instant
        case .cheer:
            pet.lastCheeredAt = instant
        case .settle:
            pet.lastFedAt = instant
            pet.lastCheeredAt = instant
        }
        document.pets[pinID] = pet
        prunePets()
        persist()
    }

    /// Returns nil when Sims is off, frozen, or the tile is not a pin.
    ///
    /// Passing `date` is for tests and previews; the live dock omits it so the debug clock applies.
    func pinState(for pinID: String, isFavorite: Bool, at date: Date? = nil) -> DockSimsPinState? {
        let usesLiveClock = date == nil
        let instant = date ?? currentTime
        guard !requiresReset, document.isEnabled, isFavorite,
              let clocks = document.clocks(for: pinID, at: instant) else { return nil }
        return DockSimsPinState(
            pinID: pinID,
            lastFedAt: clocks.fed,
            lastCheeredAt: clocks.cheered,
            intensity: document.intensity / 100,
            clockOffset: usesLiveClock ? sanitizedOffset : 0
        )
    }

    /// Moves the session care clock forward. Release builds keep the offset at zero.
    func debugAdvanceTime(by interval: TimeInterval) {
        guard interval.isFinite, interval != 0 else { return }
        debugTimeOffset = sanitizedOffset + interval
    }

    /// Returns the care clock to the wall clock. Written care stamps are left as they are.
    func debugResetTime() {
        debugTimeOffset = 0
    }

    /// Clears every pin's care history. The feature stays on; moods start playful again.
    func resetMoods(at date: Date? = nil) {
        guard !requiresReset else { return }
        document.pets = [:]
        document.baselineAt = date ?? currentTime
        storageFailed = false
        persistRemovingIfEmpty()
    }

    /// Replaces a corrupt document after an explicit reset. Sims starts disabled.
    func reset() {
        invalidateRumours()
        document = .empty
        requiresReset = false
        storageFailed = false
        debugTimeOffset = 0
        repository.remove()
    }

    private func prunePets() {
        let limit = DockSimsLimits.maximumPets
        guard document.pets.count > limit else { return }
        let kept = document.pets.values
            .sorted { lhs, rhs in
                if lhs.lastCaredAt != rhs.lastCaredAt { return lhs.lastCaredAt > rhs.lastCaredAt }
                return lhs.pinID < rhs.pinID
            }
            .prefix(limit)
        document.pets = Dictionary(uniqueKeysWithValues: kept.map { ($0.pinID, $0) })
    }

    private func persist() {
        do {
            try repository.save(document)
            storageFailed = false
        } catch {
            storageFailed = true
        }
    }

    private func persistRemovingIfEmpty() {
        if !document.isEnabled, !document.aiRumoursEnabled, document.pets.isEmpty, document.baselineAt == nil,
           document.intensity == DockSimsLimits.defaultIntensity {
            repository.remove()
            storageFailed = false
            return
        }
        persist()
    }
}
