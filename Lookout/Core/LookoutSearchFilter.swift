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

    /// The folder and type rules of `allows` as an SQL condition on the path column `column`, so a query can drop
    /// what the settings exclude before its `LIMIT`. It allows at least what `allows` does (`LIKE` ignores case for
    /// ASCII only), so `allows` still runs on what it returns, and the existence check can't be expressed here.
    ///
    /// A path is allowed when some chosen folder holds it and no skip inside that folder does, as in
    /// `FolderSelection.isSearched`. Each range is a `>=`/`<` pair on the UNIQUE path index (`Searcher.prefixRange`).
    func sqlCondition(column: String) -> (sql: String, values: [SQLValue]) {
        var values: [SQLValue] = []
        func range(_ folder: String) -> String {
            let (lower, upper) = Searcher.prefixRange(folder)
            values += [.text(lower), .text(upper)]
            return "(\(column) >= ? AND \(column) < ?)"
        }
        let byFolder = folders.map { folder in
            let inside = skipped.filter { FolderSelection.isInside($0, folder) }
            return "(" + ([range(folder)] + inside.map { "NOT " + range($0) }).joined(separator: " AND ") + ")"
        }
        var sql = byFolder.isEmpty ? "0" : "(" + byFolder.joined(separator: " OR ") + ")"
        for ext in excludedExtensions.sorted() {
            // The extension as a literal: `%`, `_` and the escape character itself mean nothing in it.
            let literal = ext.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            sql += " AND \(column) NOT LIKE ? ESCAPE '\\'"
            values.append(.text("%." + literal))
        }
        return (sql, values)
    }
}
