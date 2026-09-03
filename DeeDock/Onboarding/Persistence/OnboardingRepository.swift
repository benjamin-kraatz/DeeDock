import Foundation

/// What the tour records once a person has been through it.
///
/// A version rather than a flag, so a later release can introduce a step and show the tour
/// again to people who have only seen an earlier one.
struct OnboardingRecord: Codable, Equatable {
    /// The tour version the person completed or dismissed.
    var completedVersion: Int
}

/// Persists whether the first-launch tour still needs to be shown.
///
/// Unlike `DockSettingsRepository`, an unreadable record is not an error worth surfacing and is
/// treated as *already completed*. Onboarding that reappears every launch because a stray byte
/// cannot be decoded would be worse than onboarding a person never sees, and there is no user
/// data here to protect. `save` still refuses to overwrite nothing, so a failed write simply
/// leaves the tour pending.
struct OnboardingRepository {
    /// The tour version this build presents.
    static let currentVersion = 1

    private let defaults: UserDefaults
    private let key = "onboarding.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Returns nil only when nothing readable is stored *and* the key is absent.
    func load() -> OnboardingRecord? {
        guard let object = defaults.object(forKey: key) else { return nil }
        guard let data = object as? Data,
              let record = try? JSONDecoder().decode(OnboardingRecord.self, from: data) else {
            // Present but unreadable: assume the tour has been seen and stay quiet.
            return OnboardingRecord(completedVersion: Self.currentVersion)
        }
        return record
    }

    /// True when this build's tour has not yet been completed or dismissed.
    func needsOnboarding() -> Bool {
        guard let record = load() else { return true }
        return record.completedVersion < Self.currentVersion
    }

    /// Records completion. Encoding a two-field value cannot realistically fail; a failure
    /// leaves the previous value in place and the tour pending.
    func complete() {
        let record = OnboardingRecord(completedVersion: Self.currentVersion)
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: key)
    }
}
