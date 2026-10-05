import Foundation

/// Supplies the project's survey definitions.
nonisolated protocol AnalyticsSurveySource: Sendable {
    func surveys() async throws -> [AnalyticsSurvey]
}

/// Fixed definitions for previews and tests. Nothing touches the network.
nonisolated struct AnalyticsFixedSurveySource: AnalyticsSurveySource {
    let definitions: [AnalyticsSurvey]
    func surveys() async throws -> [AnalyticsSurvey] { definitions }
}

/// Caches survey definitions so opening the launcher does not cost a request each time.
///
/// Definitions are fetched on first demand and reused for ``freshness``. A failed fetch is not
/// retried for ``retryDelay``, so an offline Mac or a blocked host is asked rarely. Concurrent
/// callers share one request.
@MainActor
final class AnalyticsSurveyCatalog {
    static let freshness: TimeInterval = 6 * 60 * 60
    static let retryDelay: TimeInterval = 30 * 60

    private let source: (any AnalyticsSurveySource)?
    private var definitions: [AnalyticsSurvey] = []
    private var nextFetch = Date.distantPast
    private var request: Task<[AnalyticsSurvey]?, Never>?

    /// - Parameter source: nil in builds without credentials; every lookup then returns nil.
    init(source: (any AnalyticsSurveySource)?) { self.source = source }

    /// The survey with `id` when it is running and DOKK can render it.
    func survey(id: String, now: Date = Date()) async -> AnalyticsSurvey? {
        if now >= nextFetch, let source {
            let request = request ?? Task { try? await source.surveys() }
            self.request = request
            let fetched = await request.value
            // The first caller to resume records the result; later ones see it already applied.
            if self.request == request {
                self.request = nil
                if let fetched { definitions = fetched }
                nextFetch = now.addingTimeInterval(fetched == nil ? Self.retryDelay : Self.freshness)
            }
        }
        return definitions.first { $0.id == id && $0.isSupported && $0.isRunning(at: now) }
    }

    /// Forgets cached definitions, so turning sharing back on fetches them again.
    func reset() {
        request?.cancel()
        request = nil
        definitions = []
        nextFetch = .distantPast
    }
}
