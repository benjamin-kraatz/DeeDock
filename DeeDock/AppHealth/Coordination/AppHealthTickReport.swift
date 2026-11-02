import Foundation

/// What one completed tick computed, handed to labelling after the tick's records are queued for writing.
///
/// `samples` holds every watched app's sample, written or not, with responsiveness results attached. The context
/// fields describe the moment the tick ran. Labelling reads longer windows from `AppHealthController.history(for:)`.
nonisolated struct AppHealthTickReport: Sendable {
    let date: Date
    /// Seconds since the previous tick.
    let interval: Double
    /// The frontmost app's bundle identifier.
    let frontmost: String?
    /// Whole seconds since the last keyboard, mouse, or trackpad input.
    let idleSeconds: Int
    let power: AppHealthPowerSource
    let thermal: AppHealthThermalState
    /// Accessibility was already allowed, so responsiveness checks ran.
    let accessibilityTrusted: Bool
    /// Every watched app's sample, by bundle identifier.
    let samples: [String: AppHealthSample]

    /// Samples sorted by CPU use, busiest first, for pickers that list watched apps.
    var samplesByCPU: [AppHealthSample] {
        samples.values.sorted { lhs, rhs in
            lhs.cpuPercent != rhs.cpuPercent ? lhs.cpuPercent > rhs.cpuPercent : lhs.app < rhs.app
        }
    }
}
