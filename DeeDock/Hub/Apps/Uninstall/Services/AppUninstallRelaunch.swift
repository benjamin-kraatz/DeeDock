import AppKit

/// Relaunches DOKK so a new Full Disk Access grant takes effect, and remembers which uninstall to reopen.
///
/// macOS applies Full Disk Access to a process when it starts: a running DOKK keeps being denied until
/// it relaunches (verified on macOS 27). The pending entry expires after
/// ``pendingLifetime`` so a later, unrelated launch doesn't pop the sheet up.
@MainActor
enum AppUninstallRelaunch {
    static let pendingKey = "hub.uninstall.pending.v1"
    static let pendingLifetime: TimeInterval = 15 * 60

    /// Saves `appURL` as the uninstall to reopen, starts a waiter that opens DOKK again once this process
    /// has exited, and quits.
    /// - Returns: False if the waiter couldn't start; DOKK keeps running and nothing is saved.
    @discardableResult
    static func relaunch(reopening appURL: URL, defaults: UserDefaults = .standard) -> Bool {
        let waiter = Process()
        waiter.executableURL = URL(fileURLWithPath: "/bin/sh")
        // The PID and bundle path arrive as positional parameters, never inside the script text.
        waiter.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$2\"",
                            "dokk-relaunch", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path]
        waiter.standardInput = FileHandle.nullDevice
        waiter.standardOutput = FileHandle.nullDevice
        waiter.standardError = FileHandle.nullDevice
        defaults.set(["path": appURL.path, "date": Date().timeIntervalSince1970], forKey: pendingKey)
        do {
            try waiter.run()
        } catch {
            defaults.removeObject(forKey: pendingKey)
            return false
        }
        NSApp.terminate(nil)
        return true
    }

    /// The app whose uninstall was waiting for a relaunch, removed from `defaults`. Nil when there is
    /// none, it expired, or the app is gone.
    static func takePending(defaults: UserDefaults = .standard, now: Date = Date()) -> URL? {
        guard let entry = defaults.dictionary(forKey: pendingKey) else { return nil }
        defaults.removeObject(forKey: pendingKey)
        guard let path = entry["path"] as? String, let saved = entry["date"] as? TimeInterval,
              now.timeIntervalSince1970 - saved < pendingLifetime,
              FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }
}
