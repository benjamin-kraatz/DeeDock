import Foundation

/// A persistable app identity and fallback location, independent of a running process.
nonisolated struct ApplicationReference: Codable, Equatable, Identifiable, Sendable {
    /// Preferred identity across application moves and multiple running instances.
    let bundleIdentifier: String?
    /// Last known bundle location, also used as identity when a bundle identifier is absent.
    let url: URL
    /// System-provided display name retained for unavailable pinned applications.
    let name: String

    /// Optional persistent access for user-selected application bundles. Older pins decode without it.
    var bookmarkData: Data? = nil

    /// Stable key shared by persistence, ordering, and SwiftUI view identity.
    var id: String { bundleIdentifier ?? url.standardizedFileURL.path }
}
