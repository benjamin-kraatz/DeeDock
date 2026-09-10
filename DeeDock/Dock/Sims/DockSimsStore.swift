import Foundation
import Observation

/// App-wide opt-in Sims moods and the light care loop.
///
/// All state stays on this Mac. There is no rumour feed, no account, and no network call.
/// Moods are clocks: the store writes care timestamps and the overlay derives the face
/// from elapsed time. Turning the feature off hides overlays without deleting pets.
@MainActor @Observable
final class DockSimsStore {
    private(set) var document = DockSimsDocument.empty
    private(set) var requiresReset = false
    private(set) var storageFailed = false
    @ObservationIgnored private let repository: DockSimsRepository

    var isEnabled: Bool { document.isEnabled }
    var intensity: Double { document.intensity }
    var hasPets: Bool { !document.pets.isEmpty }

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

    func setEnabled(_ enabled: Bool, at date: Date = .now) {
        guard !requiresReset, document.isEnabled != enabled else { return }
        document.isEnabled = enabled
        if enabled, document.baselineAt == nil {
            document.baselineAt = date
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

    /// Feed, cheer, or settle one pinned app. Unpinned running tiles are ignored.
    func care(_ action: DockSimsCareAction, pinID: String, at date: Date = .now) {
        guard !requiresReset, document.isEnabled, DockSimsLimits.isValidPinID(pinID),
              date.timeIntervalSince1970.isFinite else { return }
        let clocks = document.clocks(for: pinID, at: date) ?? (date, date)
        var pet = DockSimsPet(pinID: pinID, lastFedAt: clocks.fed, lastCheeredAt: clocks.cheered)
        switch action {
        case .feed:
            pet.lastFedAt = date
        case .cheer:
            pet.lastCheeredAt = date
        case .settle:
            pet.lastFedAt = date
            pet.lastCheeredAt = date
        }
        document.pets[pinID] = pet
        prunePets()
        persist()
    }

    /// Returns nil when Sims is off, frozen, or the tile is not a pin.
    func pinState(for pinID: String, isFavorite: Bool, at date: Date = .now) -> DockSimsPinState? {
        guard !requiresReset, document.isEnabled, isFavorite,
              let clocks = document.clocks(for: pinID, at: date) else { return nil }
        return DockSimsPinState(
            pinID: pinID,
            lastFedAt: clocks.fed,
            lastCheeredAt: clocks.cheered,
            intensity: document.intensity / 100
        )
    }

    /// Clears every pin's care history. The feature stays on; moods start playful again.
    func resetMoods(at date: Date = .now) {
        guard !requiresReset else { return }
        document.pets = [:]
        document.baselineAt = date
        storageFailed = false
        persistRemovingIfEmpty()
    }

    /// Replaces a corrupt document after an explicit reset. Sims starts disabled.
    func reset() {
        document = .empty
        requiresReset = false
        storageFailed = false
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
        if !document.isEnabled, document.pets.isEmpty, document.baselineAt == nil,
           document.intensity == DockSimsLimits.defaultIntensity {
            repository.remove()
            storageFailed = false
            return
        }
        persist()
    }
}
