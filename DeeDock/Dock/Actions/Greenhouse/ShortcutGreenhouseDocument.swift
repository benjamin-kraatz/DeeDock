import Foundation

/// Versioned local-only greenhouse preference. Missing storage means the feature stays off.
nonisolated struct ShortcutGreenhouseDocument: Codable, Equatable, Sendable {
    var version: Int
    var isEnabled: Bool

    static let empty = ShortcutGreenhouseDocument(
        version: ShortcutGreenhouseLimits.version,
        isEnabled: false
    )

    enum CodingKeys: String, CodingKey {
        case version, isEnabled
    }

    init(version: Int = ShortcutGreenhouseLimits.version, isEnabled: Bool = false) {
        self.version = version
        self.isEnabled = isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version)
            ?? ShortcutGreenhouseLimits.version
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(isEnabled, forKey: .isEnabled)
    }

    var isValid: Bool {
        version == ShortcutGreenhouseLimits.version
    }
}

/// Storage bounds for the greenhouse preference document.
enum ShortcutGreenhouseLimits {
    static let version = 1
    static let storageKey = "dock.shortcut-greenhouse.v1"
    static let maximumEncodedBytes = 8 * 1024
}
