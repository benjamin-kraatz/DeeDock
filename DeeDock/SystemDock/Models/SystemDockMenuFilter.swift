import Foundation

/// Picks the rows an application added itself out of the menu the macOS Dock builds around them.
///
/// The Dock merges recent documents, windows, the application's own rows, Options, and its system
/// commands into one list, and Accessibility exposes no attribute that tells them apart. Titles are
/// localized by the Dock, so the sections are recognised by shape. Observed layout on macOS 27:
///
///     [recent documents] ‖ ‖ [windows] ‖ [application sections…] ‖ [Options ▸] ‖ [system commands]
///
/// Only the system section is always present. Finder has no Options row.
nonisolated enum SystemDockMenuFilter {
    /// Returns the application's own rows, with separators only between its sections.
    ///
    /// - Parameters:
    ///   - entries: The top level of the Dock's menu as read.
    ///   - windowTitles: Titles of the application's windows, which DOKK's menu already lists.
    static func applicationEntries(in entries: [SystemDockMenuEntry], windowTitles: Set<String>) -> [SystemDockMenuEntry] {
        var sections = entries.split(omittingEmptySubsequences: false, whereSeparator: \.isSeparator).map(Array.init)

        // The last section is always the Dock's Show All Windows, Hide, and Quit commands.
        guard sections.popLast() != nil else { return [] }
        // A lone submenu before them is Options. An application's own lone submenu is safe from
        // this rule because Options then sits between the two.
        if let last = sections.last, last.count == 1, !last[0].children.isEmpty { sections.removeLast() }
        // Recent documents are the one section the Dock closes with two separators.
        if sections.count >= 2, sections[1].isEmpty { sections.removeFirst(2) }
        // Only the first remaining section can be windows. The current window is checked, but an
        // application in the background has no check, so its titles are compared as well. Windows
        // on another Space are missing from those titles, which is why one match is enough.
        if let first = sections.first, first.contains(where: { $0.isChecked || windowTitles.contains($0.title) }) {
            sections.removeFirst()
        }

        return Array(sections.filter { !$0.isEmpty }.joined(separator: [.separator]))
    }
}
