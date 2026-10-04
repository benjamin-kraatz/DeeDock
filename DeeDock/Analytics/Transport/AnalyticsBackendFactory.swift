import Foundation

/// Chooses the backend for this process.
nonisolated enum AnalyticsBackendFactory {
    /// PostHog when the package is linked and the bundle carries credentials; otherwise a
    /// backend that discards everything.
    static func live() -> any AnalyticsBackend {
        #if canImport(PostHog)
        PostHogAnalyticsBackend(credentials: AnalyticsCredentials())
        #else
        NoOpAnalyticsBackend()
        #endif
    }
}
