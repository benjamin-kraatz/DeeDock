import CoreGraphics
import Observation

/// Search and keyboard selection for one compact Launcher presentation.
///
/// Results, suggestions, opening, icons, and history come from the dock's shared ``LauncherState``,
/// so both Launcher styles find, suggest, and open apps the same way. Selection is local because
/// the compact grid has its own fixed columns and no groups or mixed results to navigate.
@MainActor @Observable
final class CompactLauncherModel {
    let launcher: LauncherState
    /// The selected tile. A suggested app and its ordinary tile have separate identities.
    /// Nil until an arrow key moves into the grid.
    private(set) var selectedID: LauncherBrowseID?
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

    /// Up to three suggested apps, only while the query is empty and suggestions are on.
    var suggestions: [LauncherApplication] { launcher.suggestedApplications }

    /// Whether arrow keys currently move through the grid instead of the search field's text.
    var navigating: Bool { selectedID != nil }

    /// The Suggested row, then the grid's rows. Each section starts a row, so Up and Down keep the
    /// column when they cross from the short Suggested row into the grid.
    private var rows: [[LauncherBrowseItem]] {
        let columns = CompactLauncherLayout.columns
        let suggested = suggestions.map { LauncherBrowseItem(id: .suggested($0.id), application: $0) }
        let apps = results.map { LauncherBrowseItem(id: .application($0.id), application: $0) }
        let grid = stride(from: 0, to: apps.count, by: columns).map { Array(apps[$0..<min($0 + columns, apps.count)]) }
        return (suggested.isEmpty ? [] : [suggested]) + grid
    }

    /// Moves the selection by `distance` tiles, starting at the first tile, and stops at the ends.
    /// A distance of one row moves to the same column of the next row, or its last tile.
    func move(by distance: Int) {
        selectedID = LauncherBrowseNavigation.move(selectedID, distance: distance, columns: CompactLauncherLayout.columns,
                                                   rows: rows.map { $0.map(\.id) })
    }

    /// Opens the selected app, or the first tile when nothing is selected yet. A selection that has
    /// since disappeared, such as a suggestion marked Not Now, opens nothing rather than its neighbor.
    func openSelection() {
        let items = rows.flatMap { $0 }
        let item: LauncherBrowseItem?
        if let selectedID {
            item = items.first { $0.id == selectedID }
        } else {
            item = items.first
        }
        guard let item else { return }
        if case .suggested = item.id { launcher.openSuggested(item.application) }
        else { launcher.open(item.application) }
    }

    func clearSelection() { selectedID = nil }
}
