import Foundation

/// In-memory position owned by one display's Launcher, independent of its hosted view lifetime.
struct LauncherBrowseScroll {
    /// Offsets are reusable only when the controls and ordered app sections still match.
    struct Context: Hashable {
        let query: String
        let filter: LauncherFilter
        let locationFilter: LauncherLocationFilter
        let sort: LauncherSort
        let grouping: LauncherGrouping
        let layout: LauncherLayout
        let kind: LauncherSearchKind
        let columns: Int
        let sections: [[String]]

        init(state: LauncherState, columns: Int, groups: [LauncherState.Group]) {
            query = state.query
            filter = state.filter
            locationFilter = state.locationFilter
            sort = state.sort
            grouping = state.grouping
            layout = state.layout
            kind = state.search.kind
            self.columns = layout == .grid ? columns : 1
            sections = groups.map { [$0.id] + $0.applications.map(\.id) }
        }
    }

    let context: Context
    /// Vertical content offset in points, excluding transient rubber-band overscroll.
    let offset: CGFloat
}
