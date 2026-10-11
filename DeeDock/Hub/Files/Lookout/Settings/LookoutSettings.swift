import Foundation

/// What the person chose for Lookout, DOKK's on-device semantic file search. Persisted as JSON under `hub.lookout.v1`
/// (`LookoutSettingsRepository`).
///
/// Lookout is opt-in: it stays off until onboarding (phase 3) completes setup and turns it on. Keys missing from saved
/// data decode to their defaults, so adding a field never loses the rest.
nonisolated struct LookoutSettings: Codable, Equatable, Sendable {
    /// The person wants Lookout on.
    var enabled = false
    /// Onboarding finished: folders chosen and the model download started.
    var setupCompleted = false
    /// The folders to index, as absolute paths (with subfolders chosen on their own, as `FolderSelection` keeps them).
    var folders: [String] = []
    /// Folders skipped inside `folders`.
    var excludedFolders: [String] = []
    /// File extensions never indexed, as typed ("heic", ".txt").
    var excludedExtensions: [String] = []
    /// "Read files on battery too": when off, the backfill waits for AC power (`LookoutPowerPolicy`).
    var indexOnBattery = true

    init() {}

    /// Lookout should run: set up and turned on.
    var isActive: Bool { enabled && setupCompleted }

    /// The folders and skips as the index service and the search filter take them: chosen folders without those
    /// another one already covers, and only the skips that leave something out.
    var selection: FolderSelection { FolderSelection(chosen: folders, skipped: excludedFolders) }

    /// The settings without anything personal (no paths, no names, no extensions): safe for analytics.
    var analyticsSafe: AnalyticsSummary {
        AnalyticsSummary(enabled: enabled, setupCompleted: setupCompleted, folderCount: selection.folders.count,
                         excludedFolderCount: selection.effectiveSkips.count,
                         excludedExtensionCount: IndexOptions.extensions(excludedExtensions.joined(separator: ",")).count,
                         indexOnBattery: indexOnBattery)
    }

    /// Counts and flags only.
    struct AnalyticsSummary: Equatable, Sendable {
        let enabled: Bool
        let setupCompleted: Bool
        let folderCount: Int
        let excludedFolderCount: Int
        let excludedExtensionCount: Int
        let indexOnBattery: Bool
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, setupCompleted, folders, excludedFolders, excludedExtensions, indexOnBattery
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = LookoutSettings()
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        setupCompleted = try container.decodeIfPresent(Bool.self, forKey: .setupCompleted) ?? defaults.setupCompleted
        folders = try container.decodeIfPresent([String].self, forKey: .folders) ?? defaults.folders
        excludedFolders = try container.decodeIfPresent([String].self, forKey: .excludedFolders)
            ?? defaults.excludedFolders
        excludedExtensions = try container.decodeIfPresent([String].self, forKey: .excludedExtensions)
            ?? defaults.excludedExtensions
        indexOnBattery = try container.decodeIfPresent(Bool.self, forKey: .indexOnBattery) ?? defaults.indexOnBattery
    }
}
