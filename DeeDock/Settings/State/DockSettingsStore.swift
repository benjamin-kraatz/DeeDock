import Foundation
import Observation

/// Main-actor configuration shared by the native Settings scene and the dock controller.
@MainActor @Observable
final class DockSettingsStore {
    private(set) var value: DockSettings = .defaults
    private(set) var errorMessage: LocalizedStringResource?
    /// Corrupt preferences require an explicit reset before they can be replaced.
    private(set) var requiresReset = false
    @ObservationIgnored private let repository: DockSettingsRepository?
    /// The current panel owner observes completed edits here and clears the callback on teardown.
    @ObservationIgnored var settingsDidChange: (() -> Void)?

    /// A nil repository provides isolated, in-memory state for previews.
    init(repository: DockSettingsRepository?) {
        self.repository = repository
        do { value = try repository?.load() ?? .defaults }
        catch {
            requiresReset = true
            errorMessage = .settingsLoadError
        }
    }

    /// Publishes a valid edit only after saving succeeds; malformed input is ignored.
    func update<Value>(_ keyPath: WritableKeyPath<DockSettings, Value>, to newValue: Value) {
        guard !requiresReset else { return }
        var proposed = value
        proposed[keyPath: keyPath] = newValue
        guard let normalized = proposed.normalized, normalized != value else { return }
        save(normalized)
    }

    /// Explicitly replaces only configuration, including unreadable saved configuration.
    func restoreDefaults() { save(.defaults) }

    private func save(_ settings: DockSettings) {
        do {
            try repository?.save(settings)
            value = settings
            requiresReset = false
            errorMessage = nil
            settingsDidChange?()
        } catch { errorMessage = .settingsSaveError }
    }
}
