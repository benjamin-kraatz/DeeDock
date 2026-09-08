import Foundation

/// An app can appear in both sections without sharing selection or ScrollView identity.
nonisolated enum LauncherBrowseID: Hashable {
    case suggested(String)
    case application(String)
}

nonisolated struct LauncherBrowseItem: Identifiable {
    let id: LauncherBrowseID
    let application: LauncherApplication
}

nonisolated enum LauncherBrowseNavigation {
    /// Horizontal motion follows reading order; vertical motion preserves columns across section boundaries.
    static func move(_ selection: LauncherBrowseID?, distance: Int, columns: Int,
                     rows: [[LauncherBrowseID]]) -> LauncherBrowseID? {
        let rows = rows.filter { !$0.isEmpty }
        let items = rows.flatMap { $0 }
        guard let selection, let index = items.firstIndex(of: selection) else { return items.first }
        if columns > 1, abs(distance) == columns,
           let row = rows.firstIndex(where: { $0.contains(selection) }),
           let column = rows[row].firstIndex(of: selection) {
            let target = min(max(row + (distance > 0 ? 1 : -1), 0), rows.count - 1)
            return rows[target][min(column, rows[target].count - 1)]
        }
        return items[min(max(index + distance, 0), items.count - 1)]
    }
}
