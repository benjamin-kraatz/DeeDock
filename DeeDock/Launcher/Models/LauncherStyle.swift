import Foundation

/// How a dock presents its Launcher.
///
/// `full` morphs the dock into the searchable Launcher with suggestions, tools, Robi, and file actions.
/// `compact` opens a small app grid, led by any suggestions, above the Launcher tile and leaves the
/// dock in place. File drops
/// always use the full Launcher, because only it offers file actions.
nonisolated enum LauncherStyle: String, Codable, CaseIterable, Sendable {
    case full, compact
}
