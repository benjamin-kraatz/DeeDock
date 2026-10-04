import Foundation

/// How this build reached the Mac. TestFlight and direct builds share one PostHog project and
/// are told apart by this value and the version.
nonisolated enum AnalyticsChannel: String, AnalyticsToken {
    case direct, testflight, debug

    static var current: AnalyticsChannel {
        #if DEBUG
        .debug
        #elseif TESTFLIGHT
        .testflight
        #else
        .direct
        #endif
    }
}
