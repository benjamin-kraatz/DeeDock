import Foundation

nonisolated extension URL {
    /// Whether this file URL is `folder` or a descendant of it.
    ///
    /// Both URLs are symlink-resolved, then standardized. The check walks path components, so
    /// `/a/bc` is not inside `/a/b`. Components follow the folder volume's
    /// `volumeSupportsCaseSensitiveNames`, reading the nearest existing parent when the path
    /// itself is missing. If that resource cannot be read at all, comparison folds case, matching
    /// the default APFS volume.
    func isSameOrDescendant(of folder: URL) -> Bool {
        let child = resolvingSymlinksInPath().standardizedFileURL.folderContainmentComponents
        let parentURL = folder.resolvingSymlinksInPath().standardizedFileURL
        let parent = parentURL.folderContainmentComponents
        guard child.count >= parent.count else { return false }
        let caseSensitive = parentURL.volumeReportsCaseSensitiveNames
        return zip(parent, child).allSatisfy { lhs, rhs in
            caseSensitive ? lhs == rhs : lhs.caseInsensitiveCompare(rhs) == .orderedSame
        }
    }

    /// `standardizedFileURL` drops a trailing slash. Another directory URL can still leave an
    /// empty last component, which would make `/a/b/` disagree with `/a/b`.
    private var folderContainmentComponents: [String] {
        var components = pathComponents
        if components.last?.isEmpty == true { components.removeLast() }
        return components
    }

    /// True only when the volume explicitly supports case-sensitive names.
    ///
    /// Volume attributes can fail for a path that does not exist yet. Walk to the nearest
    /// existing parent so a missing final component still uses that volume's rule.
    private var volumeReportsCaseSensitiveNames: Bool {
        var url = self
        var previous = ""
        while url.path != previous {
            let values = try? url.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
            if let sensitive = values?.volumeSupportsCaseSensitiveNames { return sensitive }
            previous = url.path
            url.deleteLastPathComponent()
        }
        return false
    }
}
