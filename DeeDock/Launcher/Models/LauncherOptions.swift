import Foundation

nonisolated enum LauncherFilter: String, CaseIterable, Identifiable, Sendable {
    case all, running, pinned, recent
    var id: Self { self }
    var title: LocalizedStringResource {
        switch self {
        case .all: .launcherAll
        case .running: .launcherRunning
        case .pinned: .launcherPinned
        case .recent: .launcherRecent
        }
    }
}

nonisolated enum LauncherSort: String, CaseIterable, Identifiable, Sendable {
    case name, recent, frequent
    var id: Self { self }
    var title: LocalizedStringResource {
        switch self { case .name: .launcherName; case .recent: .launcherLastOpened; case .frequent: .launcherMostOpened }
    }
}

nonisolated enum LauncherGrouping: String, CaseIterable, Identifiable, Sendable {
    case none, category, letter
    var id: Self { self }
    var title: LocalizedStringResource {
        switch self { case .none: .launcherUngrouped; case .category: .launcherCategory; case .letter: .launcherAlphabetical }
    }
}

nonisolated enum LauncherLayout: String, CaseIterable, Identifiable, Sendable {
    case grid, list
    var id: Self { self }
    var title: LocalizedStringResource { self == .grid ? .launcherGrid : .launcherList }
    var symbol: String { self == .grid ? "square.grid.2x2" : "list.bullet" }
}

/// Bundle categories map to app-owned translated copy; unknown or missing metadata stays explicit.
nonisolated enum LauncherCategory {
    static func title(_ identifier: String) -> LocalizedStringResource {
        switch identifier.replacingOccurrences(of: "public.app-category.", with: "") {
        case "developer-tools": .launcherCategoryDevelopment
        case "productivity", "business", "finance": .launcherCategoryWork
        case "graphics-design", "photography", "video": .launcherCategoryCreative
        case "music", "entertainment": .launcherCategoryEntertainment
        case "social-networking", "news", "reference", "weather", "travel": .launcherCategoryInformation
        case "education", "medical", "healthcare-fitness", "lifestyle", "sports": .launcherCategoryLearning
        case "utilities": .launcherCategoryUtilities
        case let value where value.contains("games"): .launcherCategoryGames
        default: .launcherCategoryOther
        }
    }
}
