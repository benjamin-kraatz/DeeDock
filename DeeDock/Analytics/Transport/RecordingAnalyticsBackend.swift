import Foundation
import Observation

/// The most recent events handed to the backend, for the "recently sent" list in Settings.
///
/// Held in memory only. It shows what DOKK sent, not what PostHog stored: the SDK adds its own
/// default properties afterwards.
@MainActor @Observable
final class AnalyticsRecentLog {
    static let capacity = 40
    /// Newest first.
    private(set) var records: [AnalyticsRecord] = []

    init(records: [AnalyticsRecord] = []) { self.records = records }

    func append(_ record: AnalyticsRecord) {
        records.insert(record, at: 0)
        if records.count > Self.capacity { records.removeLast(records.count - Self.capacity) }
    }

    func clear() { records.removeAll() }
}

/// Forwards to another backend and keeps a copy of each captured event in an ``AnalyticsRecentLog``.
nonisolated final class RecordingAnalyticsBackend: AnalyticsBackend {
    private let base: any AnalyticsBackend
    private let log: AnalyticsRecentLog

    init(base: any AnalyticsBackend, log: AnalyticsRecentLog) {
        self.base = base
        self.log = log
    }

    var isConfigured: Bool { base.isConfigured }

    func start(personProfiles: Bool) { base.start(personProfiles: personProfiles) }

    func capture(_ record: AnalyticsRecord) {
        base.capture(record)
        Task { @MainActor [log] in log.append(record) }
    }

    func captureLog(_ record: AnalyticsLogRecord) { base.captureLog(record) }
    func captureAI(_ record: AIObservabilityRecord) { base.captureAI(record) }

    /// Lists the event by name only. Its responses are not repeated in Settings.
    func captureSurvey(_ record: AnalyticsSurveyRecord) {
        base.captureSurvey(record)
        let entry = AnalyticsRecord(name: record.name, properties: [:])
        Task { @MainActor [log] in log.append(entry) }
    }
    func register(_ properties: AnalyticsProperties) { base.register(properties) }
    func unregister(_ keys: [String]) { base.unregister(keys) }
    func setPersonProperties(_ properties: AnalyticsProperties) { base.setPersonProperties(properties) }
    func setPersonProfiles(_ enabled: Bool) { base.setPersonProfiles(enabled) }
    func resetIdentity() { base.resetIdentity() }
    func flush() { base.flush() }

    func stopAndDiscard() {
        base.stopAndDiscard()
        Task { @MainActor [log] in log.clear() }
    }
}
