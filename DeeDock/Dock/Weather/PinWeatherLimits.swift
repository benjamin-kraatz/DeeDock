import Foundation

/// Bounds for unused-pin weather. The look is polish, so the threshold stays in days, not hours.
enum PinWeatherLimits {
    /// Inclusive unused-day range offered in Settings.
    static let unusedDays = 1...90
    /// Factory default: rust starts after a month of leaving a pin untouched.
    static let defaultUnusedDays = 30
    /// Hard cap on stored pin identities so a long-lived Mac cannot grow an unbounded map.
    static let maximumEntries = 2_000
    static let maximumIDLength = 4_096
    /// UserDefaults payload ceiling; larger blobs are treated as corrupt rather than loaded.
    static let maximumEncodedBytes = 1_048_576
    static let secondsPerDay: TimeInterval = 86_400
}
