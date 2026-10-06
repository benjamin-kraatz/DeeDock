import Foundation

/// Whether this launch should send `Application updated`.
///
/// The decision is a pure comparison of the last launched version with the one now running.
/// ``UpdateAnalytics`` persists the new version only after it has handed the event to the
/// analytics layer, and it passes `analyticsEnabled: false` when sharing is off so the version
/// is recorded without an event.
nonisolated struct ApplicationUpdateLaunch: Equatable, Sendable {
    /// A marketing version and build, as stored from the last launch or read from the bundle.
    struct Snapshot: Equatable, Sendable {
        var version: String
        var build: String?
    }

    /// A version or build change that may be sent.
    struct Change: Equatable, Sendable {
        var previous: Snapshot
        var current: Snapshot
        /// Set only when this launch's version and build are the offered target of that install.
        var updateSource: ApplicationUpdateSource?
        /// The build channel (`direct` or `debug`). Nil leaves the property off the event.
        var channel: AnalyticsChannel?
    }

    /// The change to report, or nil when this launch must not send `Application updated`.
    ///
    /// Nil covers three cases: no stored version (the first install), the same version and
    /// build, and analytics switched off. A build change with the same marketing version is
    /// still a change.
    static func change(from stored: Snapshot?, to current: Snapshot, analyticsEnabled: Bool,
                       updateSource: ApplicationUpdateSource? = nil,
                       channel: AnalyticsChannel? = nil) -> Change? {
        guard analyticsEnabled, let stored else { return nil }
        guard stored.version != current.version || stored.build != current.build else { return nil }
        return Change(previous: stored, current: current, updateSource: updateSource, channel: channel)
    }
}

/// How the check that led to an install was started.
///
/// Absent when that check was not a user or background update check, including a new build
/// that appeared without Sparkle starting an install. The property is then left off the event.
nonisolated enum ApplicationUpdateSource: String, AnalyticsToken, Sendable {
    /// Sparkle's scheduled check.
    case automatic
    /// A check a person started.
    case manual

    init?(_ check: AnalyticsUpdateCheck) {
        switch check {
        case .user: self = .manual
        case .background: self = .automatic
        case .information: return nil
        }
    }
}
