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
    /// After the person picks context, Apple's on-device model suggests a few questions about it.
    /// Always on this Mac, whichever model answers.
    var suggestQuestions = true
    /// A picture of the whole window goes with every question about it, beside its text. Off,
    /// Robi takes the picture only when the window has too little accessibility text to read.
    /// Switched from the prompt bar; needs Screen Recording.
    var attachWindowPicture = false
    /// The global Option-Shift-Command-R shortcut that wakes Robi on the focused window.
    var shortcutEnabled = true
    /// Apps whose windows never get Robi, by bundle identifier.
    var excludedBundleIdentifiers: [String] = []
    /// Where the person dragged the tab on each app's windows, by bundle identifier: the tab
    /// centre's fraction of the window's width (see `RobiLayout.tabX`). Apps without an entry
    /// get the tab centred. Never reported to analytics (see `RobiStore`).
    var tabPositions: [String: Double] = [:]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case isEnabled, answerModel, claudeEffort, shortcutEnabled, excludedBundleIdentifiers, tabPositions
        case suggestQuestions, attachWindowPicture
    }

    /// Every field falls back to its default, so a document written by an older or newer build
    /// still loads instead of resetting Robi.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = (try? values.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? false
        answerModel = (try? values.decodeIfPresent(RobiAnswerModel.self, forKey: .answerModel)) ?? .onDevice
        claudeEffort = (try? values.decodeIfPresent(RobiClaudeEffort.self, forKey: .claudeEffort)) ?? .medium
        suggestQuestions = (try? values.decodeIfPresent(Bool.self, forKey: .suggestQuestions)) ?? true
        attachWindowPicture = (try? values.decodeIfPresent(Bool.self, forKey: .attachWindowPicture)) ?? false
        shortcutEnabled = (try? values.decodeIfPresent(Bool.self, forKey: .shortcutEnabled)) ?? true
        excludedBundleIdentifiers = (try? values.decodeIfPresent([String].self, forKey: .excludedBundleIdentifiers)) ?? []
        tabPositions = (try? values.decodeIfPresent([String: Double].self, forKey: .tabPositions)) ?? [:]
    }
}
