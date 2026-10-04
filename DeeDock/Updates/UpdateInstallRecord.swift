import Foundation

/// What DOKK was running when it started an automatic install.
///
/// Written right before the install replaces the app bundle and read by the next launch.
/// It stays in defaults until the user opens the installed notice or a newer offer arrives.
nonisolated struct UpdateInstallRecord: Codable, Equatable, Sendable {
    static let key = "updates.auto-installed-from.v1"

    var fromVersion: String
    var fromBuild: String?
    /// True once the post-install callout was opened or dismissed.
    var announced: Bool

    /// An install completed when the running build differs from the one that started it.
    /// The same build means the install failed or was cancelled.
    func completed(currentBuild: String?) -> Bool {
        fromBuild != currentBuild
    }

    static func load(from defaults: UserDefaults) -> UpdateInstallRecord? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(UpdateInstallRecord.self, from: data)
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }

    static func clear(in defaults: UserDefaults) {
        defaults.removeObject(forKey: key)
    }
}
