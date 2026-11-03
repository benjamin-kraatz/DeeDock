import Foundation
import OSLog

/// Deletes the clipboard copies Clipboard Museum left behind, once, after DEE-153 removed it.
///
/// The Museum stored everything in one folder, `Application Support/<bundle id>/ClipboardMuseum`:
/// `collection.json` (the exhibits and the Museum's own settings), `Images/*.png`, and redacted
/// content sealed in `Vault/*.sealed`. The Museum wrote no UserDefaults keys, so there are none to
/// remove.
///
/// `run()` deletes exactly that folder. It never enumerates or touches the rest of Application
/// Support, and a symbolic link at the folder's path is removed as a link, never followed. The
/// completion flag is set only once the folder is gone, so a failed deletion is logged and retried
/// at the next launch.
///
/// The vault's key, a generic password in the login keychain (service
/// `<bundle id>.clipboard-museum`, account `vault-key`, label "DOKK Clipboard Museum"), is left on
/// purpose. It lives in the file-based keychain, where deleting an item can show a password or
/// access prompt (a locked keychain, or an item created by a differently signed build), and
/// there's no reliable way to make that silent. A prompt at launch for a feature that's gone would
/// be worse than the leftover: once the sealed files are deleted, the key decrypts nothing.
nonisolated struct ClipboardMuseumCleanup {
    /// Set once the Museum's folder is gone. The cleanup does nothing while it is set.
    static let completedKey = "cleanup.clipboard-museum.v1"

    /// The Museum's folder, or nil when Application Support or the bundle identifier can't be
    /// resolved. The Museum fell back to the temporary folder and to "DeeDock" in those cases;
    /// a destructive cleanup must not, so it skips instead.
    static var defaultDirectory: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty else { return nil }
        return base.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("ClipboardMuseum", isDirectory: true)
    }

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DOKK", category: "Cleanup")

    private let defaults: UserDefaults
    private let directory: URL?

    /// - Parameters:
    ///   - directory: The Museum folder to delete, or nil to skip. Tests pass a temporary one.
    init(defaults: UserDefaults = .standard, directory: URL? = Self.defaultDirectory) {
        self.defaults = defaults
        self.directory = directory
    }

    /// Runs the cleanup off the main actor so deleting up to a few hundred files never delays launch.
    ///
    /// The task is not retained or cancelled: it finishes in moments, and an interrupted run is
    /// repeated at the next launch because the completion flag is written last.
    static func runInBackground() {
        Task.detached(priority: .utility) { ClipboardMuseumCleanup().run() }
    }

    /// Deletes the folder unless an earlier run finished.
    ///
    /// - Returns: True when the folder is gone and the flag is set, false when the folder could
    ///   not be resolved or deleted and the next launch should try again.
    @discardableResult
    func run() -> Bool {
        guard !defaults.bool(forKey: Self.completedKey) else { return true }
        guard let directory else {
            Self.logger.error("Skipped the Clipboard Museum cleanup: Application Support or the bundle identifier is unavailable")
            return false
        }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // Nothing was ever collected, or an earlier run deleted it before the flag was written.
        } catch {
            Self.logger.error("Could not delete the Clipboard Museum folder: \(error.localizedDescription, privacy: .public)")
            return false
        }
        defaults.set(true, forKey: Self.completedKey)
        return true
    }
}
