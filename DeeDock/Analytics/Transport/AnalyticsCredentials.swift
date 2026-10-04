import Foundation

/// The PostHog project key and ingestion host, read from Info.plist.
///
/// `Configuration/App.xcconfig` supplies both through `POSTHOG_PROJECT_TOKEN` and `POSTHOG_HOST`.
/// Nothing is hard-coded, so a build without the key collects nothing.
nonisolated struct AnalyticsCredentials: Equatable, Sendable {
    let apiKey: String
    let host: String

    /// Nil when the bundle carries no key or no usable HTTPS host.
    init?(bundle: Bundle = .main) {
        let key = (bundle.object(forInfoDictionaryKey: "DOKKAnalyticsAPIKey") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let host = (bundle.object(forInfoDictionaryKey: "DOKKAnalyticsHost") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, let url = URL(string: host), url.scheme == "https", url.host != nil else { return nil }
        apiKey = key
        self.host = host
    }
}
