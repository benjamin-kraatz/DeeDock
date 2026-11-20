import Foundation

/// Path helpers shared by the sources, the history, and the access policy.
nonisolated enum FlixPaths {
    /// An absolute path, standardized, without a trailing slash. Every stored path goes through this
    /// so the history's dedupe key is stable.
    static func standardized(_ path: String) -> String {
        let standardized = (path as NSString).standardizingPath
        return standardized.count > 1 && standardized.hasSuffix("/") ? String(standardized.dropLast()) : standardized
    }

    /// The page a download came from, reduced to scheme, host, and path so tokens in the query or
    /// fragment are never stored. `whereFroms` is `kMDItemWhereFroms`: the file's own address
    /// first, then the page that linked to it. The page is preferred when present.
    static func sourcePage(fromWhereFroms whereFroms: [String]) -> URL? {
        let candidates = whereFroms.count > 1 ? [whereFroms[1], whereFroms[0]] : whereFroms
        for candidate in candidates {
            guard var components = URLComponents(string: candidate),
                  let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  components.host?.isEmpty == false else { continue }
            components.query = nil
            components.fragment = nil
            components.user = nil
            components.password = nil
            if let url = components.url { return url }
        }
        return nil
    }

    /// The default watched folders: Desktop, Documents, Downloads, and iCloud Drive.
    static func defaultWatchedFolders(home: String = NSHomeDirectory()) -> [String] {
        ["Desktop", "Documents", "Downloads", "Library/Mobile Documents/com~apple~CloudDocs"].map {
            standardized(home + "/" + $0)
        }
    }

    /// `~/Downloads`, where new files count as downloads even without a source page.
    static func downloads(home: String = NSHomeDirectory()) -> String {
        standardized(home + "/Downloads")
    }
}
