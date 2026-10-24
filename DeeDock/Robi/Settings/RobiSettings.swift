import Foundation

/// Which model answers what the person asks Robi.
nonisolated enum RobiAnswerModel: String, Codable, CaseIterable, Sendable {
    /// Apple's on-device model. Nothing leaves the Mac.
    case onDevice = "on_device"
    /// Claude Sonnet 5.5 through the person's own Anthropic API key.
    case claude
}

/// How much effort Claude spends on one answer. Both levels are ones Sonnet 5.5 accepts.
nonisolated enum RobiClaudeEffort: String, Codable, CaseIterable, Sendable {
    case medium
    case high
}

/// Robi's app-wide preferences.
///
/// Stored apart from `DockSettings` because nothing here belongs to a dock or a display, so no
/// display profile can override it. The Anthropic API key is never part of this value: it lives
/// in the Keychain (`RobiAPIKeyStore`), because these settings are a plain UserDefaults plist.
nonisolated struct RobiSettings: Codable, Equatable, Sendable {
    /// Robi is opt-in. Showing it needs Accessibility; reading pixels needs Screen Recording.
    var isEnabled = false
    var answerModel: RobiAnswerModel = .onDevice
    var claudeEffort: RobiClaudeEffort = .medium
    /// The global Option-Shift-Command-R shortcut that wakes Robi on the focused window.
    var shortcutEnabled = true
    /// Apps whose windows never get Robi, by bundle identifier.
    var excludedBundleIdentifiers: [String] = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case isEnabled, answerModel, claudeEffort, shortcutEnabled, excludedBundleIdentifiers
    }

    /// Every field falls back to its default, so a document written by an older or newer build
    /// still loads instead of resetting Robi.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = (try? values.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? false
        answerModel = (try? values.decodeIfPresent(RobiAnswerModel.self, forKey: .answerModel)) ?? .onDevice
        claudeEffort = (try? values.decodeIfPresent(RobiClaudeEffort.self, forKey: .claudeEffort)) ?? .medium
        shortcutEnabled = (try? values.decodeIfPresent(Bool.self, forKey: .shortcutEnabled)) ?? true
        excludedBundleIdentifiers = (try? values.decodeIfPresent([String].self, forKey: .excludedBundleIdentifiers)) ?? []
    }
}
