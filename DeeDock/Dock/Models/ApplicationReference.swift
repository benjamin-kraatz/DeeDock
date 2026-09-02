import Foundation

/// A persistable app identity and fallback location, independent of a running process.
struct ApplicationReference: Codable, Equatable, Identifiable {
    /// Preferred identity across application moves and multiple running instances.
    let bundleIdentifier: String?
    /// Last known bundle location, also used as identity when a bundle identifier is absent.
    let url: URL
    /// System-provided display name retained for unavailable pinned applications.
    let name: String

    /// Stable key shared by persistence, ordering, and SwiftUI view identity.
    var id: String { bundleIdentifier ?? url.standardizedFileURL.path }
}
