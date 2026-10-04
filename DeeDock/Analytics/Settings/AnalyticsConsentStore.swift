import Foundation
import Observation

/// What a person has decided about usage data, and whether they have been told about it.
struct AnalyticsConsentRecord: Codable, Equatable {
    /// "Share anonymous usage data". On by default while DOKK is in 0.x.
    var sharingEnabled = true
    /// Whether events build an anonymous person profile holding the configuration.
    var personProfilesEnabled = true
    /// The notice version this person was shown; nil while a new user has not reached the tour's
    /// page. ``AnalyticsConsentStore/grandfatheredVersion`` marks someone who updated from a
    /// version without analytics and by decision gets no notice.
    var noticeVersion: Int?
}

/// Persists the analytics choices and gates collection on the first-launch notice.
///
/// The version exists so that 1.0 can ask again: raise ``currentNoticeVersion`` and everyone
/// whose record holds a lower number counts as not yet informed.
@MainActor @Observable
final class AnalyticsConsentStore {
    /// The notice this build presents in the tour and in Settings.
    static let currentNoticeVersion = 1
    /// Recorded for people who updated into analytics during 0.x. It is lower than every real
    /// notice version, so a later re-ask reaches them too.
    static let grandfatheredVersion = 0

    private(set) var record: AnalyticsConsentRecord
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let key = "analytics.consent.v1"

    /// - Parameters:
    ///   - defaults: nil keeps the choices in memory, for previews and tests.
    ///   - isExistingInstall: evaluated only when no record exists yet. Pass whether DOKK has
    ///     run on this Mac before analytics existed; such a person is not shown a notice.
    init(defaults: UserDefaults?, isExistingInstall: () -> Bool = { false }) {
        self.defaults = defaults
        if let data = defaults?.data(forKey: key),
           let stored = try? JSONDecoder().decode(AnalyticsConsentRecord.self, from: data) {
            record = stored
        } else {
            record = AnalyticsConsentRecord(noticeVersion: isExistingInstall() ? Self.grandfatheredVersion : nil)
            save()
        }
    }

    /// False for a new user until the tour page or the Settings card has been on screen.
    var hasSeenNotice: Bool { record.noticeVersion != nil }

    /// Whether events may be collected at all.
    var allowsCollection: Bool { record.sharingEnabled && hasSeenNotice }

    /// Records that the explanation was on screen. Does nothing once a notice is recorded.
    /// - Returns: true when this call was the one that recorded it.
    @discardableResult
    func markNoticeShown() -> Bool {
        guard record.noticeVersion == nil else { return false }
        record.noticeVersion = Self.currentNoticeVersion
        save()
        return true
    }

    func setSharingEnabled(_ enabled: Bool) {
        guard enabled != record.sharingEnabled else { return }
        record.sharingEnabled = enabled
        save()
    }

    func setPersonProfilesEnabled(_ enabled: Bool) {
        guard enabled != record.personProfilesEnabled else { return }
        record.personProfilesEnabled = enabled
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults?.set(data, forKey: key)
    }
}

extension AnalyticsConsentStore {
    /// Whether DOKK left any trace of an earlier launch in `defaults`.
    ///
    /// Must run before the dock coordinator starts, because starting it writes these keys.
    static func hasEarlierLaunch(in defaults: UserDefaults) -> Bool {
        ["onboarding.v1", "dock.settings.v1", "dock.displays.v1"].contains { defaults.object(forKey: $0) != nil }
    }
}
