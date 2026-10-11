import Foundation

/// Which of the index's files the settings still allow a search to show. A removed folder's rows (or a newly skipped
/// extension's) outlive the change until the index service syncs (indexing paused, or the app quit first), and a file
/// deleted since the last sync is still indexed: none of those may appear.
///
/// DigUp applied this to the finished hits (`Engine.search`); `Searcher` applies it to every qualifying file before
/// folders are grouped, so a folder never counts files that can't be shown.
nonisolated struct LookoutSearchFilter: Sendable, Equatable {
    /// The chosen folders (`FolderSelection.folders`).
    var folders: [String]
    /// Folders skipped inside them (`FolderSelection.effectiveSkips`).
    var skipped: [String] = []
    /// Lowercased extensions without a dot (`IndexOptions.extensions`).
    var excludedExtensions: Set<String> = []
    /// Also drop files that are no longer on disk (one `stat` each).
    var requireExisting = true

    func allows(_ path: String) -> Bool {
        FolderSelection.isSearched(path, folders: folders, skipped: skipped)
            && !excludedExtensions.contains((path as NSString).pathExtension.lowercased())
            && (!requireExisting || FileManager.default.fileExists(atPath: path))
    }
}
