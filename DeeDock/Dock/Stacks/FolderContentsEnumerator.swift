import Foundation

/// Walks one folder for item counts and contents size.
///
/// The walk stays on resource values. It does not open file contents, follow
/// aliases or symbolic links, descend through cycles, or start iCloud downloads.
nonisolated enum FolderContentsEnumerator {
    private static let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .isPackageKey, .isAliasFileKey, .isSymbolicLinkKey,
        .isHiddenKey, .fileSizeKey, .isUbiquitousItemKey
    ]
    private static let maximumDepth = 64

    /// Visible immediate children, using the same hidden-file rule as `FolderStackLoader`.
    static func listVisibleChildren(_ url: URL) throws -> [URL] {
        try Task.checkCancellation()
        return try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )
    }

    /// Immediate count plus recursive totals for `url`. Throws `CancellationError` if the task is cancelled.
    static func measure(url: URL) throws -> FolderContentsMetrics {
        let children = try listVisibleChildren(url)
        return try measure(url: url, children: children)
    }

    /// Finishes a walk whose immediate children have already been listed.
    static func measure(url: URL, children: [URL]) throws -> FolderContentsMetrics {
        var visited: Set<String> = [url.standardizedFileURL.path]
        var recursiveItems = 0
        var bytes: Int64 = 0
        var incomplete = false
        try accumulate(children, depth: 1, visited: &visited, items: &recursiveItems,
                       bytes: &bytes, incomplete: &incomplete)
        return FolderContentsMetrics(
            immediateItemCount: children.count,
            recursiveItemCount: recursiveItems,
            totalByteCount: bytes,
            completeness: incomplete ? .incomplete : .complete
        )
    }

    private static func accumulate(_ urls: [URL], depth: Int, visited: inout Set<String>,
                                   items: inout Int, bytes: inout Int64, incomplete: inout Bool) throws {
        for url in urls {
            try Task.checkCancellation()
            let path = url.standardizedFileURL.path
            guard visited.insert(path).inserted else { continue }

            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: keys)
            } catch {
                incomplete = true
                continue
            }
            guard values.isHidden != true else { continue }

            let isLink = values.isAliasFile == true || values.isSymbolicLink == true
            let isPackage = values.isPackage == true
            let isDirectory = values.isDirectory == true

            if isLink {
                items += 1
                bytes += Int64(values.fileSize ?? 0)
                continue
            }
            if isPackage {
                items += 1
                let package = try packageByteCount(at: url)
                bytes += package.bytes
                if package.incomplete { incomplete = true }
                continue
            }
            if isDirectory {
                items += 1
                guard depth < maximumDepth else {
                    incomplete = true
                    continue
                }
                let children: [URL]
                do {
                    children = try listVisibleChildren(url)
                } catch {
                    incomplete = true
                    continue
                }
                try accumulate(children, depth: depth + 1, visited: &visited, items: &items,
                               bytes: &bytes, incomplete: &incomplete)
                continue
            }

            items += 1
            bytes += Int64(values.fileSize ?? 0)
        }
    }

    /// Sums files inside a package without counting those internals as stack items.
    ///
    /// Directory metadata size is omitted. Hidden files are omitted. Links are not followed.
    private static func packageByteCount(at url: URL) throws -> (bytes: Int64, incomplete: Bool) {
        var bytes: Int64 = 0
        var incomplete = false
        let packageKeys: Set<URLResourceKey> = [
            .fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey, .isAliasFileKey, .isHiddenKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(packageKeys),
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in
                incomplete = true
                return true
            }
        ) else {
            return (0, true)
        }

        for case let child as URL in enumerator {
            try Task.checkCancellation()
            let values = try? child.resourceValues(forKeys: packageKeys)
            if values?.isHidden == true { continue }
            if values?.isSymbolicLink == true || values?.isAliasFile == true {
                bytes += Int64(values?.fileSize ?? 0)
                enumerator.skipDescendants()
                continue
            }
            if values?.isDirectory == true { continue }
            bytes += Int64(values?.fileSize ?? 0)
        }
        return (bytes, incomplete)
    }
}
