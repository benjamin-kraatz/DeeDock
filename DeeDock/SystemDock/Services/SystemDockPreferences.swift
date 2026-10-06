import AppKit

/// Reads and writes the macOS Dock's preferences and restarts the Dock.
///
/// Injected so tests and previews never touch the real Dock.
@MainActor
protocol SystemDockPreferencesServicing: AnyObject {
    /// The current value, or nil when the key is not set.
    func value(for key: SystemDockKey) -> Any?
    /// Stages a value; nil removes the key. Nothing persists until `synchronize()`.
    func setValue(_ value: Any?, for key: SystemDockKey)
    /// Whether a configuration profile forces the key, which makes writes ineffective.
    func isManaged(_ key: SystemDockKey) -> Bool
    /// Persists staged writes and refreshes cached reads. Returns false when the write failed.
    func synchronize() -> Bool
    /// Ends the Dock process so launchd starts it again with the new values.
    func restartDock()
}

/// The live `com.apple.dock` domain, through the same CFPreferences store `defaults` uses.
///
/// This works only because DOKK is not sandboxed. A sandboxed build can neither read nor
/// write another application's domain.
@MainActor
final class SystemDockPreferences: SystemDockPreferencesServicing {
    private let domain = "com.apple.dock" as CFString

    func value(for key: SystemDockKey) -> Any? {
        CFPreferencesCopyAppValue(key.rawValue as CFString, domain)
    }

    func setValue(_ value: Any?, for key: SystemDockKey) {
        CFPreferencesSetAppValue(key.rawValue as CFString, value.map { $0 as AnyObject }, domain)
    }

    func isManaged(_ key: SystemDockKey) -> Bool {
        CFPreferencesAppValueIsForced(key.rawValue as CFString, domain)
    }

    func synchronize() -> Bool {
        CFPreferencesAppSynchronize(domain)
    }

    /// Sends SIGTERM, which is what `killall Dock` does. launchd relaunches the Dock within
    /// about a second; when no Dock is running, the next one reads the new values on its own.
    func restartDock() {
        for dock in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock") {
            kill(dock.processIdentifier, SIGTERM)
        }
    }
}
