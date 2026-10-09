import Foundation
import Observation

/// One browser tab in the Files tab strip: one or two panes sharing a view mode.
///
/// The second pane is kept while split is off, so toggling split back restores it. Mutations go
/// through `HubFilesModel`, which persists them and updates which panes are active.
@MainActor @Observable
final class HubFilesBrowserTab: Identifiable {
    let id = UUID()
    private(set) var panes: [HubFilesPane]
    var isSplit: Bool
    /// Index into `panes` of the pane that receives keyboard input. Always 0 when not split.
    var activePaneIndex: Int
    var viewMode: HubFilesViewMode {
        didSet { panes.forEach { $0.showsColumns = viewMode == .columns } }
    }

    init(panes: [HubFilesPane], isSplit: Bool, activePaneIndex: Int, viewMode: HubFilesViewMode) {
        precondition(!panes.isEmpty, "A browser tab needs a pane")
        let split = isSplit && panes.count > 1
        self.panes = Array(panes.prefix(2))
        self.isSplit = split
        self.activePaneIndex = split ? min(max(activePaneIndex, 0), 1) : 0
        self.viewMode = viewMode
        panes.forEach { $0.showsColumns = viewMode == .columns }
    }

    /// The panes on screen: both when split, else the first.
    var visiblePanes: [HubFilesPane] { isSplit ? panes : [panes[0]] }

    var activePane: HubFilesPane { panes[isSplit ? activePaneIndex : 0] }

    /// Adds the second pane the first time split is turned on.
    func ensureSecondPane(_ make: () -> HubFilesPane) {
        guard panes.count < 2 else { return }
        let pane = make()
        pane.showsColumns = viewMode == .columns
        panes.append(pane)
    }
}
