import Foundation

/// Temporary developer comparison preference. Both engines consume the same retained history.
nonisolated enum LauncherSuggestionEngine: String, Codable, CaseIterable, Identifiable, Sendable {
    case baseline
    case coreML

    /// Shipping engine; development overrides never change the Release selection.
    static let defaultEngine: Self = .coreML

    var id: Self { self }
    var modelVersion: String {
        switch self {
        case .baseline: LauncherSuggestionBaseline.version
        case .coreML: "coreml-knn-v1"
        }
    }
}
