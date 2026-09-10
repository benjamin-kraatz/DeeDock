import Foundation
import Observation

/// App-wide opt-in for Shortcut greenhouse chrome.
///
/// The store owns only the preference. Discovery and runs stay on ``ActionTilesController``.
/// Turning the feature off hides every plant without changing pinned shortcuts.
@MainActor @Observable
final class ShortcutGreenhouseStore {
    private(set) var document = ShortcutGreenhouseDocument.empty
    private(set) var requiresReset = false
    private(set) var storageFailed = false
    @ObservationIgnored private let repository: ShortcutGreenhouseRepository
    @ObservationIgnored var changed: (() -> Void)?

    var isEnabled: Bool { document.isEnabled }

    init(repository: ShortcutGreenhouseRepository = ShortcutGreenhouseRepository()) {
        self.repository = repository
    }

    /// Loads the stored preference. A missing key leaves the greenhouse off.
    func start() {
        do {
            if let stored = try repository.load() {
                document = stored
            }
        } catch {
            requiresReset = true
            storageFailed = true
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard !requiresReset, document.isEnabled != enabled else { return }
        document.isEnabled = enabled
        persist()
        changed?()
    }

    /// Replaces a corrupt document after an explicit reset. The greenhouse starts disabled.
    func reset() {
        document = .empty
        requiresReset = false
        storageFailed = false
        repository.remove()
        changed?()
    }

    func stop() {
        changed = nil
    }

    private func persist() {
        if !document.isEnabled {
            repository.remove()
            storageFailed = false
            return
        }
        do {
            try repository.save(document)
            storageFailed = false
        } catch {
            storageFailed = true
        }
    }
}
