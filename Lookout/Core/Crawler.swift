// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

import Darwin
import Foundation
import UniformTypeIdentifiers

/// Walks the chosen folders and applies `Rules`. Reads metadata only, never file contents (except the 600-byte
/// sniff that tells a real MPEG-TS video from a TypeScript file), plus one Spotlight query per folder for last-used
/// dates (`LastUsedDates`).
///
/// Hidden files and folders and bundle contents are never walked. Symbolic links are never followed: the enumerator
/// doesn't descend into a linked folder, and a linked file is reported as a "link or special file".
nonisolated enum Crawler {
    /// - Parameters:
    ///   - roots: The chosen folders. The whole disk (`/`) is never walked (`Rules.isAllowedRoot`).
    ///   - readsLastUsed: Whether to ask Spotlight when each file was last used. A count for an estimate doesn't need
    ///     it.
    ///   - home: The home folder whose `Library` is never walked (tests pass a folder of their own).
    static func crawl(_ roots: [URL], options: IndexOptions, readsLastUsed: Bool = true,
                      home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> CrawlReport {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentTypeKey, .isUbiquitousItemKey,
                                      .ubiquitousItemDownloadingStatusKey]
        var report = CrawlReport()
        var projectRoots = Set<String>()
        var found: [Candidate] = []
        var foundPaths = Set<String>()   // a folder inside another root would be walked twice
        let allowed = roots.map { $0.standardizedFileURL }.filter { Rules.isAllowedRoot($0.path) }
        if allowed.count < roots.count { report.skippedFolders["the whole disk", default: 0] += roots.count - allowed.count }
        let rootPaths = Set(allowed.map(\.path))

        for root in allowed {
            if Rules.isProjectRoot(root.path) { projectRoots.insert(root.path) }
            // A skip applies inside the chosen folders that contain it: a folder chosen inside a skipped one is
            // walked whole (`FolderSelection`). The walk reports real paths (/private/var, where the root says /var).
            let real = FolderSelection.realPath(root.path)
            let skips = options.excludedFolders.filter {
                FolderSelection.isInside($0, root.path) || FolderSelection.isInside($0, real)
            }.flatMap { [$0, FolderSelection.realPath($0)] }
            guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: keys,
                                             options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                             errorHandler: { _, _ in true }) else { continue }
            func visit(_ url: URL) {
                let values = try? url.resourceValues(forKeys: Set(keys))
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
                    found.append(Candidate(path: url.path, kind: kind, size: Int64(info.st_size), mtime: mtime,
                                           inode: UInt64(info.st_ino), device: UInt64(bitPattern: Int64(info.st_dev))))
                }
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
            let dates = LastUsedDates.query(allowed.map { FolderSelection.realPath($0.path) })
            if !dates.isEmpty {
                for index in kept.indices { kept[index].lastUsed = dates[kept[index].path] }
            }
        }
        report.candidates = kept
        return report
    }
}
