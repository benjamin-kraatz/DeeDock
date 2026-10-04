import Foundation

/// Which kind of build is running. Release and debug builds share one PostHog project and are
/// told apart by this value and the version.
nonisolated enum AnalyticsChannel: String, AnalyticsToken {
    case direct, debug

    static var current: AnalyticsChannel {
        #if DEBUG
        .debug
        #else
        .direct
        #endif
    }
}
