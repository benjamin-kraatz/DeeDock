import Foundation
import Observation

/// App-wide last-used times and unused-day threshold for pin weather.
///
/// Records only DDock pin use: opening, hiding, or revealing a pinned app or folder from
/// the dock. Hover, magnification, and apps launched outside DDock do not write timestamps.
@MainActor @Observable
final class PinWeatherStore {
    private(set) var document = PinWeatherDocument()
    private(set) var requiresReset = false
    private(set) var storageFailed = false
    @ObservationIgnored private let repository: PinWeatherRepository

    var enabled: Bool { document.enabled }
    var unusedDays: Int { document.unusedDays }
    var isEmpty: Bool { document.lastUsed.isEmpty }

    init(repository: PinWeatherRepository = PinWeatherRepository()) {
        self.repository = repository
    }

    /// Loads stored timestamps. Corrupt bytes freeze edits until an explicit reset.
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

    func setEnabled(_ enabled: Bool) {
        guard !requiresReset, document.enabled != enabled else { return }
        document.enabled = enabled
        persist()
    }

    func setUnusedDays(_ days: Int) {
        guard !requiresReset, PinWeatherLimits.unusedDays.contains(days), document.unusedDays != days else { return }
        document.unusedDays = days
        persist()
    }

    /// Marks a pin as just used so any rust clears. Records even when weather is hidden
    /// so turning the effect on later reflects real DDock use.
    func recordUse(_ id: String, at date: Date = .now) {
        guard !requiresReset else { return }
        let key = sanitized(id)
        guard !key.isEmpty else { return }
        document.lastUsed[key] = date
        persist()
    }

    /// Stamps unseen current pins with `now` so they start clean, and drops identities
    /// that are no longer pinned on any display.
    func synchronize(pinIDs: Set<String>, at date: Date = .now) {
        guard !requiresReset else { return }
        let ids = Set(pinIDs.compactMap { id -> String? in
            let key = sanitized(id)
            return key.isEmpty ? nil : key
        })
        var lastUsed = document.lastUsed
        var changed = false
        for id in lastUsed.keys where !ids.contains(id) {
            lastUsed.removeValue(forKey: id)
            changed = true
        }
        for id in ids where lastUsed[id] == nil {
            lastUsed[id] = date
            changed = true
        }
        if lastUsed.count > PinWeatherLimits.maximumEntries {
            let overflow = lastUsed.count - PinWeatherLimits.maximumEntries
            let oldest = lastUsed.sorted { $0.value < $1.value }.prefix(overflow).map(\.key)
            for id in oldest { lastUsed.removeValue(forKey: id) }
            changed = true
        }
        guard changed else { return }
        document.lastUsed = lastUsed
        persist()
    }

    func lastUsed(for id: String) -> Date? {
        document.lastUsed[sanitized(id)]
    }

    /// Current rust amount for a pin. Missing timestamps evaluate as unused-for-zero.
    func intensity(for id: String, at date: Date = .now) -> Double {
        PinWeatherIntensity.value(lastUsed: lastUsed(for: id), unusedDays: document.unusedDays,
                                  enabled: document.enabled, now: date)
    }

    func sample(for id: String) -> PinWeatherSample {
        PinWeatherSample(enabled: document.enabled, unusedDays: document.unusedDays,
                         lastUsed: lastUsed(for: id))
    }

    /// Forgets last-used times without changing the threshold. The next synchronize stamps
    /// current pins as now, so rust stays off until they sit unused again.
    func clearTimestamps() {
        guard !requiresReset else { return }
        document.lastUsed = [:]
        storageFailed = false
        persistRemovingIfEmpty()
    }

    /// Replaces a corrupt document after an explicit reset. Weather starts enabled.
    func reset() {
        document = PinWeatherDocument()
        requiresReset = false
        storageFailed = false
        repository.remove()
    }

    private func sanitized(_ id: String) -> String {
        String(id.prefix(PinWeatherLimits.maximumIDLength))
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
        if document.lastUsed.isEmpty, document.enabled, document.unusedDays == PinWeatherLimits.defaultUnusedDays {
            repository.remove()
            storageFailed = false
            return
        }
        persist()
    }
}
