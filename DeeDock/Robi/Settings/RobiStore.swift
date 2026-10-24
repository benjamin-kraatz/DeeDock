import Foundation
import Observation

/// Persists Robi's preferences and reports whether an Anthropic API key is saved.
///
/// Settings changes are reported to analytics by reflection, which sends Booleans, enum tokens and
/// list counts only. The excluded apps travel as a count, never as bundle identifiers.
@MainActor @Observable
final class RobiStore {
    var settings: RobiSettings { didSet {
        guard settings != oldValue else { return }
        if let data = try? JSONEncoder().encode(settings) { defaults?.set(data, forKey: Self.key) }
        if defaults != nil { Analytics.shared.settingsChanged(from: oldValue, to: settings, area: .robi) }
        changed?()
    } }
    /// True when the Keychain holds a key. The key itself is never kept in memory here.
    private(set) var hasClaudeKey: Bool
    @ObservationIgnored var changed: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let keychain: RobiAPIKeyStoring
    private static let key = "robi.settings.v1"

    /// Passing nil creates an inert preview store without reading or writing preferences.
    init(defaults: UserDefaults? = .standard, keychain: RobiAPIKeyStoring = RobiAPIKeyStore()) {
        self.defaults = defaults
        self.keychain = keychain
        settings = defaults?.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(RobiSettings.self, from: $0) } ?? .init()
        hasClaudeKey = defaults != nil && keychain.read() != nil
    }

    /// Saves a pasted key after trimming whitespace. Returns false when it is empty or the
    /// Keychain refused it.
    @discardableResult
    func saveClaudeKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, defaults != nil else { return false }
        let saved = keychain.save(trimmed)
        hasClaudeKey = keychain.read() != nil
        if saved { changed?() }
        return saved
    }

    func removeClaudeKey() {
        guard defaults != nil else { return }
        keychain.delete()
        hasClaudeKey = false
        changed?()
    }

    /// Read only when a request is about to go out.
    func claudeKey() -> String? { defaults == nil ? nil : keychain.read() }

    func setExcluded(_ bundleIdentifier: String, _ excluded: Bool) {
        var list = settings.excludedBundleIdentifiers.filter { $0 != bundleIdentifier }
        if excluded { list.append(bundleIdentifier) }
        settings.excludedBundleIdentifiers = list
    }
}
