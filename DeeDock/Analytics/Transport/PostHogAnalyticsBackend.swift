#if canImport(PostHog)
import Foundation
import PostHog

/// Sends analytics through posthog-ios. This is the only file that imports the SDK.
///
/// The file compiles to nothing until the PostHog package is linked, and
/// ``AnalyticsBackendFactory`` then falls back to the no-op backend.
///
/// The SDK's payloads are left alone: default properties such as `$device_name` stay, and no
/// sanitizer is installed. The SDK's own lifecycle events (`Application Installed`,
/// `Application Updated`, `Application Opened`) are relied on instead of DOKK events.
///
/// Autocapture is left at what the SDK offers on macOS, which today is lifecycle events only.
/// Element autocapture and session replay are compiled for iOS and Mac Catalyst only. If a later
/// SDK version adds AppKit element autocapture it would read accessibility labels, which in DOKK
/// are app names. See docs/ANALYTICS.md before raising the pinned SDK version.
nonisolated final class PostHogAnalyticsBackend: AnalyticsBackend, @unchecked Sendable {
    private let credentials: AnalyticsCredentials?
    /// Touched only by ``Analytics``, which serializes every call. The SDK reads
    /// `personProfiles` from this object on each event, so changing it takes effect at once.
    private var config: PostHogConfig?

    init(credentials: AnalyticsCredentials?) { self.credentials = credentials }

    var isConfigured: Bool { credentials != nil }

    func start(personProfiles: Bool) {
        guard let credentials, config == nil else { return }
        let config = PostHogConfig(projectToken: credentials.apiKey, host: credentials.host)
        // Only explicit calls to `captureLog` below leave the app as PostHog Logs.
        config.logs.serviceName = "DeeDock"
        config.captureApplicationLifecycleEvents = true
        config.errorTrackingConfig.autoCapture = true
        config.personProfiles = personProfiles ? .always : .never
        // Consent lives in AnalyticsConsentStore. While sharing is off the SDK is not set up
        // at all, so its own persisted opt-out flag would only be a second source of truth.
        config.optOut = false
        self.config = config
        PostHogSDK.shared.setup(config)
        if PostHogSDK.shared.isOptOut() { PostHogSDK.shared.optIn() }
    }

    func capture(_ record: AnalyticsRecord) {
        guard config != nil else { return }
        PostHogSDK.shared.capture(record.name, properties: record.properties.payload)
    }

    /// Dedicated exporter channel; existing os.Logger output is intentionally not forwarded.
    func captureLog(_ record: AnalyticsLogRecord) {
        guard config != nil else { return }
        switch record.level {
        case .info:
            PostHogSDK.shared.captureLog(record.message, level: .info, attributes: record.attributes.payload)
        case .warn:
            PostHogSDK.shared.captureLog(record.message, level: .warn, attributes: record.attributes.payload)
        case .error:
            PostHogSDK.shared.captureLog(record.message, level: .error, attributes: record.attributes.payload)
        }
    }

    func captureAI(_ record: AIObservabilityRecord) {
        guard config != nil else { return }
        PostHogSDK.shared.capture(record.name, properties: record.properties)
    }

    func register(_ properties: AnalyticsProperties) {
        guard config != nil, !properties.isEmpty else { return }
        PostHogSDK.shared.register(properties.payload)
    }

    func unregister(_ keys: [String]) {
        guard config != nil else { return }
        keys.forEach(PostHogSDK.shared.unregister)
    }

    func setPersonProperties(_ properties: AnalyticsProperties) {
        guard config != nil, !properties.isEmpty else { return }
        PostHogSDK.shared.setPersonProperties(userPropertiesToSet: properties.payload)
    }

    func setPersonProfiles(_ enabled: Bool) {
        config?.personProfiles = enabled ? .always : .never
    }

    func resetIdentity() {
        guard config != nil else { return }
        PostHogSDK.shared.reset()
    }

    func flush() {
        guard config != nil else { return }
        PostHogSDK.shared.flush()
    }

    func stopAndDiscard() {
        guard let config else { return }
        self.config = nil
        PostHogSDK.shared.close()
        // The SDK has no public call that empties its queue, so the queue folders are removed
        // once the SDK has let go of them. The folder names are the SDK's storage keys in
        // 3.89.0 (PostHogStorage.StorageKey); recheck them when the pinned version changes.
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let bundleID = Bundle.main.bundleIdentifier,
              let folder = support?.appendingPathComponent(bundleID).appendingPathComponent(config.projectToken)
        else { return }
        for name in ["posthog.queueFolder.uuid", "posthog.queueFolder", "posthog.replayFolder.uuid", "posthog.logsFolder"] {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }
}
#endif
