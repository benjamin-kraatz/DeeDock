import Foundation

/// Fetches survey definitions from PostHog's public `GET /api/surveys/?token=<project token>`.
///
/// posthog-ios loads surveys only on iOS, so this is a plain request with the public project
/// token, through the same host (and reverse proxy) as event ingestion. The session is
/// ephemeral: no cookies or cache on disk. A definition that fails to decode is skipped
/// instead of failing the whole list.
nonisolated struct PostHogSurveySource: AnalyticsSurveySource {
    private let url: URL

    init?(credentials: AnalyticsCredentials?) {
        guard let credentials, var components = URLComponents(string: credentials.host) else { return nil }
        components.path = components.path.trimmingSuffix("/") + "/api/surveys/"
        components.queryItems = [URLQueryItem(name: "token", value: credentials.apiKey)]
        guard let url = components.url else { return nil }
        self.url = url
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    func surveys() async throws -> [AnalyticsSurvey] {
        let (data, response) = try await Self.session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(Envelope.self, from: data).surveys.compactMap(\.value)
    }

    private struct Envelope: Decodable {
        let surveys: [Lenient]
    }

    private struct Lenient: Decodable {
        let value: AnalyticsSurvey?
        init(from decoder: any Decoder) throws { value = try? AnalyticsSurvey(from: decoder) }
    }
}

private extension String {
    nonisolated func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
