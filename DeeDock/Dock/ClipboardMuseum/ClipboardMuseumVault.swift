import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// Everything a redacted exhibit hides, encrypted as one blob.
nonisolated struct ClipboardVeiledPayload: Codable, Equatable, Sendable {
    var text: String?
    var image: Data?
    var recognizedText: String?

    var isEmpty: Bool { text == nil && image == nil && recognizedText == nil }
}

/// AES-GCM sealing for redacted content. The key is injected so tests never touch the Keychain.
nonisolated struct ClipboardMuseumVault: Sendable {
    let key: @Sendable () throws -> SymmetricKey

    /// Production vault: one 256-bit key in the login Keychain, created on first use.
    static let keychain = ClipboardMuseumVault(key: { try ClipboardVaultKeychain.key() })

    func seal(_ payload: ClipboardVeiledPayload) throws -> Data {
        let box = try AES.GCM.seal(JSONEncoder().encode(payload), using: key())
        guard let combined = box.combined else { throw CocoaError(.coderInvalidValue) }
        return combined
    }

    func open(_ data: Data) throws -> ClipboardVeiledPayload {
        let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key())
        return try JSONDecoder().decode(ClipboardVeiledPayload.self, from: plain)
    }
}

/// Stores the vault key as a generic password that never syncs to iCloud Keychain.
///
/// DDock is not sandboxed and has no keychain-access-group entitlement, so this uses the file-based
/// login keychain. That keychain cannot require Touch ID per item; the reveal gate is
/// ``ClipboardMuseumAuthenticator`` in the app. The key protects the vault files at rest.
nonisolated enum ClipboardVaultKeychain {
    static let service = (Bundle.main.bundleIdentifier ?? "DeeDock") + ".clipboard-museum"
    static let account = "vault-key"

    static func key() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "DDock Clipboard Museum",
            kSecAttrSynchronizable as String: false,
            kSecValueData as String: data,
        ]
        let added = SecItemAdd(attributes as CFDictionary, nil)
        guard added == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(added)) }
        return key
    }
}

/// Asks for Touch ID, Apple Watch, or the login password before hidden content is shown.
@MainActor
enum ClipboardMuseumAuthenticator {
    /// - Parameter reason: Completes macOS's "DDock is trying to …" sentence.
    /// - Returns: False when the person cancels, fails, or the Mac has no owner authentication.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
