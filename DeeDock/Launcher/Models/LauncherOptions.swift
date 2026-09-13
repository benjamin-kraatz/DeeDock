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

/// Restricts browsing and app search by where a bundle lives on disk.
///
/// Independent of ``LauncherFilter``, which still selects All / Running / Pinned / Recent.
/// Matching uses lexical path prefixes only and does not query the filesystem.
nonisolated enum LauncherLocationFilter: String, CaseIterable, Identifiable, Sendable {
    /// Every application the library already discovered.
    case all
    /// Bundles under `/Applications` or `~/Applications`.
    case applicationsFolders
    /// Applications folders plus `/System/Applications`.
    case standardMacLocations

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .all: .launcherLocationAll
        case .applicationsFolders: .launcherApplicationsFolders
        case .standardMacLocations: .launcherStandardMacLocations
        }
    }

    /// Returns whether `url` sits under one of this filter's allowed roots.
    ///
    /// Home is expanded through `home`. Comparison is case-insensitive, treats `/System/Volumes/Data`
    /// as the firmlink prefix for `/`, and requires a path-component boundary so `/ApplicationsExtra`
    /// does not match `/Applications`.
    /// - Parameters:
    ///   - url: Bundle URL already held by the launcher library.
    ///   - home: The user's home directory. Tests inject a fixed path; production uses the current home.
    func includes(_ url: URL, home: URL) -> Bool {
        switch self {
        case .all:
            return true
        case .applicationsFolders:
            return Self.isUnder(url, roots: Self.applicationsRoots(home: home))
        case .standardMacLocations:
            return Self.isUnder(url, roots: Self.standardMacRoots(home: home))
        }
    }

    private static func applicationsRoots(home: URL) -> [String] {
        let homePath = comparablePath(home)
        let userApplications = homePath == "/" ? "/applications" : homePath + "/applications"
        return [comparablePath("/Applications"), userApplications]
    }

    private static func standardMacRoots(home: URL) -> [String] {
        applicationsRoots(home: home) + [comparablePath("/System/Applications")]
    }

    private static func isUnder(_ url: URL, roots: [String]) -> Bool {
        let path = comparablePath(url)
        return roots.contains { root in
            path == root || path.hasPrefix(root + "/")
        }
    }

    /// Lexical only. `standardizedFileURL` and symlink resolution would query the filesystem.
    private static func comparablePath(_ url: URL) -> String {
        comparablePath(url.standardized.path)
    }

    private static func comparablePath(_ path: String) -> String {
        var value = path
        if value.count > 1, value.hasSuffix("/") {
            value.removeLast()
        }
        value = value.lowercased()
        let dataVolume = "/system/volumes/data"
        if value == dataVolume { return "/" }
        if value.hasPrefix(dataVolume + "/") {
            value.removeFirst(dataVolume.count)
        }
        return value
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
