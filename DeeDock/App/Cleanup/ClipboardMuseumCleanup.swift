import Foundation
import OSLog
import Security

/// Deletes the clipboard copies Clipboard Museum left behind, once, after DEE-153 removed it.
///
/// The Museum stored everything in one folder, `Application Support/<bundle id>/ClipboardMuseum`:
/// `collection.json` (the exhibits and the Museum's own settings), `Images/*.png`, and redacted
/// content sealed in `Vault/*.sealed`. The key for the sealed files was one generic-password item
/// in the login keychain, service `<bundle id>.clipboard-museum`, account `vault-key`. The Museum
/// wrote no UserDefaults keys, so there are none to remove.
///
/// `run()` deletes exactly that folder and that keychain item. It never enumerates or touches the
/// rest of Application Support, and a symbolic link at the folder's path is removed as a link,
/// never followed. The completion flag is set only once the folder is gone, so a failed deletion is
/// logged and retried at the next launch. A keychain failure is logged and not retried: without
/// the sealed files the key opens nothing. Both steps are safe to repeat.
nonisolated struct ClipboardMuseumCleanup {
    /// Set once the Museum's folder is gone. The cleanup does nothing while it is set.
    static let completedKey = "cleanup.clipboard-museum.v1"
    static let keychainAccount = "vault-key"

    /// The same service name the Museum's vault used, including its bundle identifier fallback.
    static var keychainService: String { (Bundle.main.bundleIdentifier ?? "DeeDock") + ".clipboard-museum" }

    /// The Museum's folder, resolved exactly as its repository did.
    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "DeeDock", isDirectory: true)
            .appendingPathComponent("ClipboardMuseum", isDirectory: true)
    }

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DOKK", category: "Cleanup")

    private let defaults: UserDefaults
    private let directory: URL
    private let deleteKey: () -> OSStatus

    /// - Parameters:
    ///   - directory: The Museum folder to delete. Tests pass a temporary one.
    ///   - deleteKey: Deletes the vault key and returns the keychain status. Tests pass a stub so
    ///     they never touch the real keychain.
    init(defaults: UserDefaults = .standard, directory: URL = Self.defaultDirectory,
         deleteKey: @escaping () -> OSStatus = Self.deleteKeychainItem) {
        self.defaults = defaults
        self.directory = directory
        self.deleteKey = deleteKey
    }

    /// Runs the cleanup off the main actor so deleting up to a few hundred files never delays launch.
    ///
    /// The task is not retained or cancelled: it finishes in moments, and an interrupted run is
    /// repeated at the next launch because the completion flag is written last.
    static func runInBackground() {
        Task.detached(priority: .utility) { ClipboardMuseumCleanup().run() }
    }

    /// Deletes the folder and the vault key unless an earlier run finished.
    ///
    /// - Returns: True when the folder is gone and the flag is set, false when the folder could
    ///   not be deleted and the next launch should try again.
    @discardableResult
    func run() -> Bool {
        guard !defaults.bool(forKey: Self.completedKey) else { return true }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // Nothing was ever collected, or an earlier run deleted it before the flag was written.
        } catch {
            Self.logger.error("Could not delete the Clipboard Museum folder: \(error.localizedDescription, privacy: .public)")
            return false
        }
        let status = deleteKey()
        if status != errSecSuccess, status != errSecItemNotFound {
            Self.logger.error("Could not delete the Clipboard Museum vault key: OSStatus \(status, privacy: .public)")
        }
        defaults.set(true, forKey: Self.completedKey)
        return true
    }

    /// Deletes the Museum's vault key from the login keychain. Matches on service and account only.
    static func deleteKeychainItem() -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        return SecItemDelete(query as CFDictionary)
    }
}
