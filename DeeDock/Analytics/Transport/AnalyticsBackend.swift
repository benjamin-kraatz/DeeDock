import Foundation

/// One event as it leaves the typed layer: a name and vetted property values.
nonisolated struct AnalyticsRecord: Equatable, Sendable, Identifiable {
    let id = UUID()
    let name: String
    let properties: AnalyticsProperties
    let date: Date

    init(name: String, properties: AnalyticsProperties, date: Date = Date()) {
        self.name = name
        self.properties = properties
        self.date = date
    }
}

/// A purpose-written operational log record. Only callers in this integration use this channel.
nonisolated struct AnalyticsLogRecord: Sendable {
    enum Level: Sendable {
        case info
        case warn
        case error
    }

    let message: String
    let level: Level
    let attributes: AnalyticsProperties

    init(message: String, level: Level = .info, attributes: AnalyticsProperties = [:]) {
        self.message = message
        self.level = level
        self.attributes = attributes
    }
}

/// Where analytics go once ``Analytics`` has decided they may be sent.
///
/// ``Analytics`` calls `start` on the main actor and everything else on one serial queue, so an
/// implementation sees its calls in order and never concurrently. Calls before `start` or after
/// `stopAndDiscard` must be ignored.
nonisolated protocol AnalyticsBackend: AnyObject, Sendable {
    /// Whether this backend can deliver anything. False without an API key.
    var isConfigured: Bool { get }

    /// Begins collecting. Safe to call again after `stopAndDiscard`.
    func start(personProfiles: Bool)
    func capture(_ record: AnalyticsRecord)
    /// Emits an operational log line created by this integration only.
    func captureLog(_ record: AnalyticsLogRecord)
    /// Captures the AI-specific payload documented by PostHog AI Observability.
    func captureAI(_ record: AIObservabilityRecord)
    /// Attaches `properties` to every later event until replaced or unregistered.
    func register(_ properties: AnalyticsProperties)
    func unregister(_ keys: [String])
    /// Stores `properties` on the anonymous person profile. Ignored while profiles are off.
    func setPersonProperties(_ properties: AnalyticsProperties)
    func setPersonProfiles(_ enabled: Bool)
    /// Replaces the anonymous ID and forgets registered properties.
    func resetIdentity()
    /// Asks for queued events to be uploaded now.
    func flush()
    /// Stops collecting at once and deletes every event that has not been uploaded.
    func stopAndDiscard()
}

/// Discards everything. Used by previews, tests, and builds without an API key.
nonisolated final class NoOpAnalyticsBackend: AnalyticsBackend {
    let isConfigured: Bool

    /// - Parameter isConfigured: previews pass `true` to show the Settings card's live state.
    init(isConfigured: Bool = false) { self.isConfigured = isConfigured }

    func start(personProfiles: Bool) {}
    func capture(_ record: AnalyticsRecord) {}
    func captureLog(_ record: AnalyticsLogRecord) {}
    func captureAI(_ record: AIObservabilityRecord) {}
    func register(_ properties: AnalyticsProperties) {}
    func unregister(_ keys: [String]) {}
    func setPersonProperties(_ properties: AnalyticsProperties) {}
    func setPersonProfiles(_ enabled: Bool) {}
    func resetIdentity() {}
    func flush() {}
    func stopAndDiscard() {}
}
