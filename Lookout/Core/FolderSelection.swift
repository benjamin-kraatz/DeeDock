// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

import Darwin
import Foundation

/// Which folders Lookout searches: the folders you chose, minus the folders you skipped inside them. A skip applies
/// inside the chosen folders that contain it, and a chosen folder is searched whole even inside a skipped one (skip
/// Downloads/Media, still choose Downloads/Media/Courses). The crawler, the search filter and the folder lists in
/// onboarding and Settings all follow this rule.
///
/// The folder lists show folders with one level of their subfolders, each with a checkbox. A subfolder can be searched
/// without the rest of its folder (it's chosen on its own), or left out of a folder that's searched (it's skipped).
nonisolated struct FolderSelection: Equatable, Sendable {
    /// A folder's checkbox: all of it, some of its subfolders, or none.
    enum Mark: Sendable {
        case on, mixed, off
    }

    private(set) var chosen: [String]
    private(set) var skipped: [String]
    /// Folders already searched (when Settings adds more): whatever is clicked, they stay.
    let kept: [String]

    init(chosen: [String] = [], skipped: [String] = [], kept: [String] = []) {
        self.chosen = Self.unique(chosen)
        self.skipped = Self.unique(skipped)
        self.kept = Self.unique(kept)
    }

    /// Whether `path` (a folder or a file) is searched.
    func isSearched(_ path: String) -> Bool {
        Self.isSearched(path, folders: kept + chosen, skipped: skipped)
    }

    static func isSearched(_ path: String, folders: [String], skipped: [String]) -> Bool {
        folders.contains { folder in
            (path == folder || isInside(path, folder))
                && !skipped.contains { skip in isInside(skip, folder) && (path == skip || isInside(path, skip)) }
        }
    }

    /// The closest chosen (or kept) folder that searches `path`.
    func searchedAs(_ path: String) -> String? {
        (kept + chosen).filter { folder in
            (path == folder || Self.isInside(path, folder)) && Self.isSearched(path, folders: [folder], skipped: skipped)
        }.max { $0.count < $1.count }
    }

    /// What the indexer gets: kept and chosen folders, without those another one already searches whole.
    var folders: [String] {
        let all = Self.unique(kept + chosen)
        return all.filter { folder in
            !all.contains { other in
                other != folder && Self.isInside(folder, other)
                    && Self.isSearched(folder, folders: [other], skipped: skipped)
            }
        }
    }

    /// The skips that leave something out (inside a folder that's searched).
    var effectiveSkips: [String] {
        let folders = self.folders
        return skipped.filter { skip in folders.contains { Self.isInside(skip, $0) } }
    }

    /// A folder's checkbox: mixed when some of its subfolders are skipped (it's searched) or chosen (it isn't).
    /// Deeper choices don't show here; the folder lists name them.
    func mark(_ folder: String) -> Mark {
        if isSearched(folder) {
            return skipped.contains { Self.parent($0) == folder && !isSearched($0) } ? .mixed : .on
        }
        return (kept + chosen).contains { Self.parent($0) == folder } ? .mixed : .off
    }

    /// Checks or unchecks a folder and its subfolders: all of it, or none of it.
    mutating func setFolder(_ folder: String, on: Bool) {
        skipped.removeAll { Self.parent($0) == folder }
        chosen.removeAll { Self.parent($0) == folder }
        setSubfolder(folder, on: on)
    }

    /// Checks or unchecks one folder, leaving the choices inside it as they are.
    mutating func setSubfolder(_ folder: String, on: Bool) {
        if on {
            skipped.removeAll { $0 == folder }
            if !isSearched(folder) { chosen.append(folder) }
        } else {
            chosen.removeAll { $0 == folder }
            if isSearched(folder) { skipped.append(folder) }
        }
    }

    /// Stops skipping `folder` (without choosing it).
    mutating func unskip(_ folder: String) {
        skipped.removeAll { $0 == folder }
    }

    /// Whether `path` is strictly inside `folder` (a sibling whose name merely starts the same isn't).
    static func isInside(_ path: String, _ folder: String) -> Bool {
        path.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
    }

    static func parent(_ path: String) -> String {
        (path as NSString).deletingLastPathComponent
    }

    /// The path as a walk of the folder reports it (/private/var where `standardizedFileURL` says /var).
    static func realPath(_ path: String) -> String {
        guard let real = realpath(path, nil) else { return path }
        defer { free(real) }
        return String(cString: real)
    }

    private static func unique(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }
}
