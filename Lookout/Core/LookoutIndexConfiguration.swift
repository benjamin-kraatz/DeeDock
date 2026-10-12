import Foundation

/// What the app tells the index service to index (`LookoutIndexServing.start`). Paths are absolute.
nonisolated struct LookoutIndexConfiguration: Codable, Sendable, Equatable {
    /// The folders the user chose (`FolderSelection.folders`). Files under none of them leave the index. Folders Lookout
    /// never reads (`Rules.RootRefusal`) are dropped by `allowedRoots`.
    var roots: [String]
    /// Folders skipped inside the roots (`FolderSelection.effectiveSkips`).
    var excludedFolders: [String] = []
    /// File extensions never indexed, as typed ("heic", ".txt"): normalized by `IndexOptions.extensions`.
    var excludedExtensions: [String] = []
    /// Where the model files are (`LookoutPaths.models`).
    var modelsFolder: String
    /// The folder `index.sqlite` is in (`LookoutPaths.index`).
    var indexFolder: String
    /// The power policy's verdict at start; `setBackfillAllowed` updates it.
    var backfillAllowed: Bool

    /// The indexing settings this configuration asks for.
    var options: IndexOptions {
        var options = IndexOptions()
        options.excludedFolders = excludedFolders
        options.excludedExtensions = IndexOptions.extensions(excludedExtensions.joined(separator: ","))
        return options
    }

    /// The roots that may be indexed, as folder URLs of their real paths (what the crawl reports, so pruning and the
    /// store's scope compare like with like). A root that isn't there stays as given.
    ///
    /// Each saved root is checked again here, as given and on its real path (`Rules.checkRoots`): the app refused
    /// these folders when they were picked, but a chosen folder may since have become a link to ~/Library, and the
    /// configuration may come from an older version. A refused root is left out, so `IndexWork` prunes its files.
    var allowedRoots: [URL] {
        Rules.checkRoots(roots).allowed.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    func encoded() throws -> Data { try LookoutJSON.encode(self) }

    static func decode(_ data: Data) throws -> LookoutIndexConfiguration {
        try LookoutJSON.decode(LookoutIndexConfiguration.self, from: data)
    }
}
