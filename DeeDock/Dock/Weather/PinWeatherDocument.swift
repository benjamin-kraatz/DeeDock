import Foundation

/// Local unused-pin weather preferences and last-used times.
///
/// Timestamps are written only by DDock pin use. Nothing is imported from Screen Time,
/// Launch Services recents, or other applications. A missing last-used date is treated as
/// "just now" so existing pins do not rust on upgrade.
nonisolated struct PinWeatherDocument: Codable, Equatable, Sendable {
    var enabled: Bool
    var unusedDays: Int
    var lastUsed: [String: Date]

    init(enabled: Bool = true, unusedDays: Int = PinWeatherLimits.defaultUnusedDays,
         lastUsed: [String: Date] = [:]) {
        self.enabled = enabled
        self.unusedDays = unusedDays
        self.lastUsed = lastUsed
    }

    var isValid: Bool {
        PinWeatherLimits.unusedDays.contains(unusedDays)
            && lastUsed.count <= PinWeatherLimits.maximumEntries
            && lastUsed.keys.allSatisfy { !$0.isEmpty && $0.count <= PinWeatherLimits.maximumIDLength }
    }

    private enum CodingKeys: String, CodingKey { case enabled, unusedDays, lastUsed }

    /// Absent keys take defaults so an older empty document can gain the feature without failing.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        unusedDays = try values.decodeIfPresent(Int.self, forKey: .unusedDays) ?? PinWeatherLimits.defaultUnusedDays
        lastUsed = try values.decodeIfPresent([String: Date].self, forKey: .lastUsed) ?? [:]
    }
}

/// Maps unused time onto a 0...1 rust amount. Zero until the threshold, then a gentle start
/// that weathers further over another unused-day span so the look is age, not an alarm.
enum PinWeatherIntensity {
    /// - Parameters:
    ///   - lastUsed: When the pin was last used in DDock. `nil` means "now" so unknown pins stay clean.
    ///   - unusedDays: Settings threshold. Values outside the allowed range produce no rust.
    ///   - enabled: When false, intensity is always zero. Timestamps may still be recorded.
    ///   - now: Evaluation instant, injected so tests do not depend on the wall clock.
    static func value(lastUsed: Date?, unusedDays: Int, enabled: Bool, now: Date) -> Double {
        guard enabled, PinWeatherLimits.unusedDays.contains(unusedDays) else { return 0 }
        let start = lastUsed ?? now
        let unused = now.timeIntervalSince(start)
        guard unused.isFinite, unused >= 0 else { return 0 }
        let threshold = Double(unusedDays) * PinWeatherLimits.secondsPerDay
        guard unused >= threshold else { return 0 }
        let extra = (unused - threshold) / threshold
        return min(1, 0.32 + 0.68 * min(1, extra.isFinite ? extra : 0))
    }
}

/// Values a pin icon needs to draw weather without holding the store.
struct PinWeatherSample: Equatable, Sendable {
    var enabled: Bool
    var unusedDays: Int
    var lastUsed: Date?

    /// Current rust amount at `date`.
    func intensity(at date: Date) -> Double {
        PinWeatherIntensity.value(lastUsed: lastUsed, unusedDays: unusedDays, enabled: enabled, now: date)
    }
}
