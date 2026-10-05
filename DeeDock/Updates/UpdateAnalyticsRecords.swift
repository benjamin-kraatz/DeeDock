import Foundation

/// The version and build of the last launch, so the next one can tell that DOKK changed.
///
/// Kept apart from ``UpdateInstallRecord``, which drives the What's New notice and is
/// cleared when the person reads it.
nonisolated struct UpdateLaunchRecord: Codable, Equatable, Sendable {
    static let key = "analytics.updates.last-launch.v1"

    var version: String
    var build: String?

    static func load(from defaults: UserDefaults) -> UpdateLaunchRecord? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(UpdateLaunchRecord.self, from: data)
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

/// An install DOKK started, written right before the app bundle may be replaced.
///
/// The next launch reads it once: a different build means the install completed, the same
/// build means it did not. Either way it is then removed.
nonisolated struct UpdatePendingInstallRecord: Codable, Equatable, Sendable {
    static let key = "analytics.updates.pending-install.v1"

    var fromVersion: String
    var fromBuild: String?
    var offerVersion: String?
    var offerBuild: String?
    /// Raw value of ``AnalyticsUpdateInstallPath``.
    var path: String
    var startedAt: Date

    /// Whether the running build is the one that started this install.
    func isSameBuild(version: String, build: String?) -> Bool {
        fromVersion == version && fromBuild == build
    }

    static func load(from defaults: UserDefaults) -> UpdatePendingInstallRecord? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(UpdatePendingInstallRecord.self, from: data)
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }

    static func clear(in defaults: UserDefaults) {
        defaults.removeObject(forKey: key)
    }
}
