import Foundation

/// One row of the menu the macOS Dock shows for an application, read through Accessibility.
///
/// Titles come from the application or macOS and are shown as they are. Entries are value
/// snapshots: Accessibility handles stay inside `SystemDockMenuReader`, and pressing an entry
/// reopens the Dock's menu and finds the row again through `path`.
nonisolated struct SystemDockMenuEntry: Equatable, Sendable {
    /// One level of the route to a row. The title is kept so a press can tell that the menu
    /// changed since it was read instead of pressing whatever now sits at that index.
    struct Step: Equatable, Sendable {
        let index: Int
        let title: String
    }

    let title: String
    let isEnabled: Bool
    let isChecked: Bool
    /// The route from the top of the Dock's menu to this row, in the menu as read.
    let path: [Step]
    let children: [SystemDockMenuEntry]

    /// The Dock exposes separators as rows without a title.
    var isSeparator: Bool { title.isEmpty }

    static let separator = SystemDockMenuEntry(title: "", isEnabled: false, isChecked: false, path: [], children: [])
}
