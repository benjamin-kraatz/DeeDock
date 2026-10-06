import Foundation

/// The version and build of the last launch, so the next one can tell that DOKK changed.
///
/// Stored in the defaults of the running bundle, so a Dev build (`de.benjaminkraatz.DeeDock.dev`)
/// and a Release build do not see each other's last launch. Kept apart from
/// ``UpdateInstallRecord``, which drives the What's New notice and is cleared when the person
/// reads it.
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

/// An install DOKK started, written before the authorization dialog.
///
/// The next launch reads it once and removes it. ``UpdateAnalytics/aborted(_:)`` also removes
/// it for every abort, including a cancelled authorization prompt, so a cancelled attempt
/// cannot label a later install. `update_source` is used only when this launch's version and
/// build equal the offered target.
nonisolated struct UpdatePendingInstallRecord: Codable, Equatable, Sendable {
    static let key = "analytics.updates.pending-install.v1"

    var fromVersion: String
    var fromBuild: String?
    /// Marketing version Sparkle offered for this install.
    var offerVersion: String?
    /// Build Sparkle offered for this install.
    var offerBuild: String?
    /// Raw value of ``AnalyticsUpdateInstallPath``.
    var path: String
    /// Raw value of ``ApplicationUpdateSource``, when the check that started this install was known.
    var updateSource: String? = nil
    var startedAt: Date

    /// Whether the running build is the one that started this install.
    func isSameBuild(version: String, build: String?) -> Bool {
        fromVersion == version && fromBuild == build
    }

    /// Whether `version` and `build` are the offered target. A missing offer never matches.
    func matchesTarget(version: String, build: String?) -> Bool {
        offerVersion != nil && offerBuild != nil && offerVersion == version && offerBuild == build
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
