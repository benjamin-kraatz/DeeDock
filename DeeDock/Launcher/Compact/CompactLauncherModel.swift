import CoreGraphics
import Observation

/// Search and keyboard selection for one compact Launcher presentation.
///
/// Results, opening, icons, and history come from the dock's shared ``LauncherState``, so both
/// Launcher styles find and open apps the same way. Selection is local because the compact grid
/// has no suggestions, groups, or mixed results to navigate.
@MainActor @Observable
final class CompactLauncherModel {
    let launcher: LauncherState
    /// The selected app's ID. Nil until an arrow key moves into the grid.
    private(set) var selectedID: String?
    /// Where the pointer sits, published by the popover before the content is built.
    var chrome = DockPopoverChrome(edge: .bottom, attachment: 0)

    init(launcher: LauncherState) {
        self.launcher = launcher
    }

    /// Writes through to the shared Launcher query, which owns result filtering and memoization.
    var query: String {
        get { launcher.query }
        set {
            guard newValue != launcher.query else { return }
            launcher.query = newValue
            selectedID = nil
        }
    }

    var results: [LauncherApplication] { launcher.results }

    /// Whether arrow keys currently move through the grid instead of the search field's text.
    var navigating: Bool { selectedID != nil }

    /// Moves the selection by `distance` tiles, starting at the first result, and stops at the ends.
    func move(by distance: Int) {
        let results = results
        guard !results.isEmpty else { selectedID = nil; return }
        let current = selectedID.flatMap { id in results.firstIndex { $0.id == id } }
        let next = current.map { min(max($0 + distance, 0), results.count - 1) } ?? 0
        selectedID = results[next].id
    }

    /// Opens the selected app, or the best match when nothing is selected yet.
    func openSelection() {
        let results = results
        guard let application = selectedID.flatMap({ id in results.first { $0.id == id } }) ?? results.first
        else { return }
        launcher.open(application)
    }

    func clearSelection() { selectedID = nil }
}
