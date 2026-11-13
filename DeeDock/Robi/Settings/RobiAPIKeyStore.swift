import Foundation
import Security

/// Reads and writes the person's Anthropic API key.
nonisolated protocol RobiAPIKeyStoring: Sendable {
    /// The saved key. Decrypts the secret, so call it only when a request is about to go out.
    func read() -> String?
    /// Whether a key is saved, without reading the secret. Safe at launch: it never asks macOS
    /// to decrypt the item, so it can't raise a Keychain access prompt.
    func exists() -> Bool
    @discardableResult func save(_ key: String) -> Bool
    func delete()
}

/// The Anthropic API key as a generic password in the login Keychain.
///
/// The item lives in the file-based login keychain, not the data protection keychain (the query
/// has no `kSecUseDataProtectionKeychain`). There, macOS ignores `kSecAttrAccessible`, so the
/// "this device only, after first unlock" class set on save does not apply. What protects the item:
/// it is not synchronizable, so it never leaves this Mac through iCloud Keychain; the login keychain
/// is encrypted with the person's login password; and the item's access control list trusts only
/// the app that created it, by code signature. A differently signed build (such as an unsigned
/// debug build) is asked by macOS before it may read the secret.
nonisolated struct RobiAPIKeyStore: RobiAPIKeyStoring {
    private var service: String { (Bundle.main.bundleIdentifier ?? "de.benjaminkraatz.DeeDock") + ".robi.anthropic" }
    private let account = "anthropic-api-key"

    private var query: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
         kSecAttrSynchronizable: false]
    }

    func read() -> String? {
        var request = query
        request[kSecReturnData] = true
        request[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    func exists() -> Bool {
        // No `kSecReturnData`: matching on attributes alone never decrypts the secret, so it
        // can't prompt at launch, before the dock exists, even for a differently signed build.
        var request = query
        request[kSecMatchLimit] = kSecMatchLimitOne
        return SecItemCopyMatching(request as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    func save(_ key: String) -> Bool {
        let data = Data(key.utf8)
        let update: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var attributes = query
        attributes[kSecValueData] = data
        // Ignored by the file-based keychain this item lives in; kept so the item carries the
        // intended class should it ever move to the data protection keychain.
        attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attributes[kSecAttrLabel] = "DOKK Robi – Anthropic API key"
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

/// An in-memory key store for previews and tests.
nonisolated final class RobiMemoryKeyStore: RobiAPIKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var key: String?

    init(key: String? = nil) { self.key = key }

    func read() -> String? { lock.withLock { key } }
    func exists() -> Bool { lock.withLock { key?.isEmpty == false } }
    func save(_ key: String) -> Bool { lock.withLock { self.key = key }; return true }
    func delete() { lock.withLock { key = nil } }
}
