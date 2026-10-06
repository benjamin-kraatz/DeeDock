#if DEBUG
import Foundation

/// A `com.apple.dock` stand-in for previews and tests; it never touches the real Dock.
@MainActor
final class InMemorySystemDockPreferences: SystemDockPreferencesServicing {
    /// What has been synchronized, which is what a fresh read returns.
    var stored: [SystemDockKey: Any]
    private var staged: [SystemDockKey: Any?] = [:]
    var managedKeys: Set<SystemDockKey> = []
    /// Set to false to simulate a write `cfprefsd` rejected.
    var synchronizeSucceeds = true
    private(set) var restartCount = 0

    init(_ stored: [SystemDockKey: Any] = [:]) {
        self.stored = stored
    }

    func value(for key: SystemDockKey) -> Any? {
        if let pending = staged[key] { return pending }
        return stored[key]
    }

    func setValue(_ value: Any?, for key: SystemDockKey) {
        staged[key] = .some(value)
    }

    func isManaged(_ key: SystemDockKey) -> Bool { managedKeys.contains(key) }

    func synchronize() -> Bool {
        defer { staged.removeAll() }
        guard synchronizeSucceeds else { return false }
        for (key, value) in staged { stored[key] = value }
        return true
    }

    func restartDock() { restartCount += 1 }
}

/// Live controllers over scratch storage, for previews that want a working button.
enum SystemDockTuckPreview {
    @MainActor static func controller(suite: String = "preview.systemDockTuck") -> SystemDockTuckController {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return SystemDockTuckController(service: InMemorySystemDockPreferences([.autohide: false, .tileSize: 48]),
                                        repository: SystemDockTuckRepository(defaults: defaults))
    }
}
#endif
