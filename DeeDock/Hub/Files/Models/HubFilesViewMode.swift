import Foundation

/// How a browser tab lays out its panes' items. Shared by both panes of a split tab.
nonisolated enum HubFilesViewMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case list
    case icons
    case columns

    var id: Self { self }

    /// SF Symbol for the status bar's segmented control.
    var symbolName: String {
        switch self {
        case .list: "list.bullet"
        case .icons: "square.grid.2x2"
        case .columns: "rectangle.split.3x1"
        }
    }

    /// Accessibility label and help text.
    var title: LocalizedStringResource {
        switch self {
        case .list: .hubFilesViewList
        case .icons: .hubFilesViewIcons
        case .columns: .hubFilesViewColumns
        }
    }
}
