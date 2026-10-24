import Foundation
import Security

/// Reads and writes the person's Anthropic API key.
nonisolated protocol RobiAPIKeyStoring: Sendable {
    func read() -> String?
    @discardableResult func save(_ key: String) -> Bool
    func delete()
}

/// The Anthropic API key as a generic password in the login Keychain.
///
/// The item is this-device-only and never synchronized through iCloud Keychain. DOKK is not
/// sandboxed and has no access group, so the item belongs to DOKK's code signature: a differently
/// signed build (such as an unsigned debug build) is asked by macOS before it may read it.
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

    @discardableResult
    func save(_ key: String) -> Bool {
        let data = Data(key.utf8)
        let update: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var attributes = query
        attributes[kSecValueData] = data
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
    func save(_ key: String) -> Bool { lock.withLock { self.key = key }; return true }
    func delete() { lock.withLock { key = nil } }
}
