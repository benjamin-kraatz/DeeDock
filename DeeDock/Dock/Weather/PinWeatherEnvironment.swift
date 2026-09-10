import SwiftUI

/// Per-icon weather sample. Absent or a zero-intensity sample draws no rust.
private struct PinWeatherSampleKey: EnvironmentKey {
    static let defaultValue: PinWeatherSample? = nil
}

extension EnvironmentValues {
    /// Last-used sample for the current dock icon. Running-only tiles leave this nil.
    var pinWeatherSample: PinWeatherSample? {
        get { self[PinWeatherSampleKey.self] }
        set { self[PinWeatherSampleKey.self] = newValue }
    }
}
