import Foundation

nonisolated extension URL {
    /// Whether this file URL is `folder` or a descendant of it.
    ///
    /// The check walks path components, so `/a/bc` is not inside `/a/b`.
    ///
    /// - Parameter resolvingSymlinks: When `true` (the default), both URLs are symlink-resolved,
    ///   then standardized, and components follow the folder volume's
    ///   `volumeSupportsCaseSensitiveNames`. A missing path uses the nearest existing parent.
    ///   If that resource cannot be read, comparison folds case, matching the default APFS volume.
    ///   When `false`, components are standardized lexically and compared without case. That path
    ///   does not call `standardizedFileURL`, resolve symlinks, or read volume attributes.
    ///   `standardizedFileURL` can still consult the file system for `..` and a `/private` prefix.
    ///   `close(within:)` uses the lexical path on the main thread while a volume is unmounting.
    func isSameOrDescendant(of folder: URL, resolvingSymlinks: Bool = true) -> Bool {
        if resolvingSymlinks {
            let parentURL = folder.resolvingSymlinksInPath().standardizedFileURL
            return Self.components(resolvingSymlinksInPath().standardizedFileURL.folderContainmentComponents,
                                    havePrefix: parentURL.folderContainmentComponents,
                                    caseSensitive: parentURL.volumeReportsCaseSensitiveNames)
        }
        return Self.components(lexicalFolderContainmentComponents,
                                havePrefix: folder.lexicalFolderContainmentComponents,
                                caseSensitive: false)
    }

    /// Drops `.` and empty pieces and collapses `..` using only the URL string.
    private var lexicalFolderContainmentComponents: [String] {
        var components: [String] = []
        for component in pathComponents where component != "." && !component.isEmpty {
            if component == ".." {
                if components.count > 1 { components.removeLast() }
                continue
            }
            components.append(component)
        }
        return components
    }

    private static func components(_ child: [String], havePrefix parent: [String], caseSensitive: Bool) -> Bool {
        guard child.count >= parent.count else { return false }
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
