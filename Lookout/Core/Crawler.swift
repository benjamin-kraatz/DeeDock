// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

import Darwin
import Foundation
import UniformTypeIdentifiers

/// Walks the chosen folders and applies `Rules`. Reads metadata only, never file contents, plus one Spotlight query per
/// folder for last-used dates (`LastUsedDates`).
///
/// Hidden files and folders and bundle contents are never walked. Symbolic links are never followed: the enumerator
/// doesn't descend into a linked folder, and a linked file is reported as a "link or special file". A package that is
/// one document (`Rules.packageDocuments`, an `.rtfd`) is indexed as one file, the package, and its contents are
/// never walked either.
nonisolated enum Crawler {
    /// How many files the walk finds between two `found` reports.
    static let foundReportInterval = 250

    /// - Parameters:
    ///   - roots: The chosen folders. Each is checked again on its real path, the root itself included
    ///     (`Rules.checkRoots`), and a refused one (the whole disk, the home folder, ~/Library, a hidden, bundle or
    ///     system folder) is not walked.
    ///   - readsLastUsed: Whether to ask Spotlight when each file was last used. A count for an estimate doesn't need
    ///     it.
    ///   - home: The home folder, never a root, whose `Library` is never walked (tests pass a folder of their own).
    ///   - found: Hears how many files to index the walk has found so far, every `foundReportInterval` files, while
    ///     it walks (the progress's "still counting"). The count is before code projects and datasets are left out.
    static func crawl(_ roots: [URL], options: IndexOptions, readsLastUsed: Bool = true,
                      home: String = FileManager.default.homeDirectoryForCurrentUser.path,
                      found onFound: ((Int) -> Void)? = nil) -> CrawlReport {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentTypeKey, .isUbiquitousItemKey,
                                      .ubiquitousItemDownloadingStatusKey]
        var report = CrawlReport()
        var projectRoots = Set<String>()
        var found: [Candidate] = []
        var foundPaths = Set<String>()   // a folder inside another root would be walked twice
        func add(_ candidate: Candidate) {
            found.append(candidate)
            if found.count.isMultiple(of: foundReportInterval) { onFound?(found.count) }
        }
        // Checked here too, not only when the configuration arrives: a chosen folder that has become a link to
        // ~/Library resolves there now and is refused. The walk starts at the real path, so it never goes through a
        // link, and it reports real paths (/private/var, where a root says /var).
        let checked = Rules.checkRoots(roots.map(\.path), home: home)
        for refused in checked.refused { report.skippedFolders[refused.refusal.reason, default: 0] += 1 }
        let allowed = checked.allowed.map { URL(fileURLWithPath: $0, isDirectory: true) }
        report.roots = checked.allowed
        let rootPaths = Set(checked.allowed)
        // Skips as given and as real paths, to compare with the real paths the walk reports.
        let excluded = options.excludedFolders.flatMap { [$0, FolderSelection.realPath($0)] }

        for root in allowed {
            if Rules.isProjectRoot(root.path) { projectRoots.insert(root.path) }
            // A skip applies inside the chosen folders that contain it: a folder chosen inside a skipped one is
            // walked whole (`FolderSelection`).
            let skips = excluded.filter { FolderSelection.isInside($0, root.path) }
            guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: keys,
                                             options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                             errorHandler: { _, _ in true }) else { continue }
            func visit(_ url: URL) {
                let values = try? url.resourceValues(forKeys: Set(keys))
                if values?.isDirectory == true, let entry = Rules.packageDocumentEntry(url) {
                    // Never walked into, also where macOS doesn't call it a package.
                    walker.skipDescendants()
                    visitPackageDocument(url, entry: entry, values: values)
                    return
                }
                if values?.isDirectory == true, values?.isPackage != true {
                    if let reason = Rules.skipReason(forFolder: url, home: home, excluded: skips) {
                        walker.skipDescendants()
                        report.skippedFolders[reason, default: 0] += 1
                    } else if Rules.isProjectRoot(url.path) {
                        projectRoots.insert(url.path)
                    }
                    return
                }
                if values?.isPackage == true {
                    report.skipped["app or bundle", default: 0] += 1
                    return
                }
                switch Rules.classify(url, type: values?.contentType, options: options) {
                case .ignore:
                    report.skipped["other type", default: 0] += 1
                case .skip(let reason):
                    report.skipped[reason, default: 0] += 1
                case .index(let kind):
                    var info = stat()
                    guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
                        report.skipped["link or special file", default: 0] += 1
                        return
                    }
                    // Reading a dataless placeholder (iCloud "Optimize Mac Storage", File Providers) downloads it.
                    let dataless = info.st_flags & 0x4000_0000 != 0  // SF_DATALESS
                    let inCloud = values?.isUbiquitousItem == true && values?.ubiquitousItemDownloadingStatus != .current
                    if dataless || inCloud {
                        report.skipped["in the cloud, not downloaded", default: 0] += 1
                        return
                    }
                    guard foundPaths.insert(url.path).inserted else { return }
                    let mtime = Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9
                    add(Candidate(path: url.path, kind: kind, size: Int64(info.st_size), mtime: mtime,
                                  inode: UInt64(info.st_ino), device: UInt64(bitPattern: Int64(info.st_dev))))
                }
            }

            /// A package that is one document: the package itself, never a link, with the file that holds its text
            /// (`entry`) a regular file inside it. Its identity is the package's inode, so a save that replaces the
            /// package is a new file; its size and date are the entry's, so an edit in place is seen as a change.
            func visitPackageDocument(_ url: URL, entry: String, values: URLResourceValues?) {
                let kind: FileKind
                switch Rules.classify(url, type: values?.contentType, options: options) {
                case .index(let indexed): kind = indexed
                case .skip(let reason): report.skipped[reason, default: 0] += 1; return
                case .ignore: report.skipped["other type", default: 0] += 1; return
                }
                var package = stat(), inner = stat()
                guard lstat(url.path, &package) == 0, (package.st_mode & S_IFMT) == S_IFDIR,
                      lstat(url.appendingPathComponent(entry).path, &inner) == 0, (inner.st_mode & S_IFMT) == S_IFREG
                else {
                    report.skipped["link or special file", default: 0] += 1
                    return
                }
                let dataless = (package.st_flags | inner.st_flags) & 0x4000_0000 != 0  // SF_DATALESS
                let inCloud = values?.isUbiquitousItem == true && values?.ubiquitousItemDownloadingStatus != .current
                if dataless || inCloud {
                    report.skipped["in the cloud, not downloaded", default: 0] += 1
                    return
                }
                guard foundPaths.insert(url.path).inserted else { return }
                let mtime = Double(inner.st_mtimespec.tv_sec) + Double(inner.st_mtimespec.tv_nsec) / 1e9
                add(Candidate(path: url.path, kind: kind, size: Int64(inner.st_size), mtime: mtime,
                              inode: UInt64(package.st_ino), device: UInt64(bitPattern: Int64(package.st_dev))))
            }

            // URL resource values are autoreleased; draining per file keeps a big walk from piling them up (the
            // service crawls on a dispatch queue whose pool only drains when the whole sync is done).
            while let url = autoreleasepool(invoking: { walker.nextObject() as? URL }) {
                autoreleasepool {
                    visit(url)
                }
            }
        }

        // Inside a code project only screenshots count (assets, fixtures and datasets don't).
        var inProject: [String: Bool] = [:]
        func isInProject(_ folder: String) -> Bool {
            if let known = inProject[folder] { return known }
            let parent = (folder as NSString).deletingLastPathComponent
            let answer = projectRoots.contains(folder) || (parent != folder && parent.count > 1 && isInProject(parent))
            inProject[folder] = answer
            return answer
        }
        var kept: [Candidate] = []
        for file in found {
            if file.kind != .screenshot, isInProject((file.path as NSString).deletingLastPathComponent) {
                report.skipped["inside a code project", default: 0] += 1
            } else {
                kept.append(file)
            }
        }

        if !options.includeDatasets {
            let datasets = Rules.datasetFolders(kept.map {
                (($0.path as NSString).deletingLastPathComponent,
                 (($0.path as NSString).lastPathComponent as NSString).deletingPathExtension, $0.kind)
            }, roots: rootPaths)
            if !datasets.isEmpty {
                report.datasets = datasets
                kept.removeAll { file in
                    let skip = datasets[(file.path as NSString).deletingLastPathComponent] != nil && file.kind == .image
                    if skip { report.skipped["dataset", default: 0] += 1 }
                    return skip
                }
            }
        }

        if readsLastUsed, !kept.isEmpty {
            let dates = LastUsedDates.query(checked.allowed)
            if !dates.isEmpty {
                for index in kept.indices { kept[index].lastUsed = dates[kept[index].path] }
            }
        }
        report.candidates = kept
        return report
    }
}
