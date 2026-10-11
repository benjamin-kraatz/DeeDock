// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

/// Indexing settings. Anything that changes vectors is part of `fingerprint`; an index never mixes settings.
nonisolated struct IndexOptions: Sendable, Equatable {
    var includeDatasets = false
    /// Images whose longer side is shorter than this are skipped (icons, thumbnails, spacer GIFs).
    var minImageSide = 256
    /// Long files are read a step at a time: the first step in the first pass (every file gets searchable sooner), the
    /// rest after everything else (`Indexer.finishLongFiles`). PDFs up to `bigPDFPages` are read whole at once.
    var bigPDFPages = 50
    var pdfStep = 30                // pages
    var docStep = 40                // chunks, ~64,000 characters
    /// Only machine-made giants get this far: a file's pages or chunks past these are left out.
    var maxPages = 5_000
    var maxChunks = 5_000           // ~8 million characters
    var minPageText = 200           // fewer characters than this: embed the rendered page instead
    var photoBudget = 140           // vision soft tokens: 70 / 140 / 280 / 560 / 1120
    var screenshotBudget = 280
    var pageBudget = 280
    /// Folders not to walk into (absolute paths). A folder chosen inside one of them is still walked whole
    /// (`FolderSelection`).
    var excludedFolders: [String] = []
    /// Lowercased extensions without a dot (`extensions(_:)` turns what people type into these).
    var excludedExtensions: Set<String> = []

    init() {}

    /// File extensions as people write them ("HEIC, .txt *.md") → ["heic", "txt", "md"].
    static func extensions(_ text: String) -> Set<String> {
        Set(text.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map { word in
            word.drop { $0 == "*" || $0 == "." }.lowercased()
        }.filter { !$0.isEmpty })
    }

    /// The settings that shape vectors, stored with the index (`meta.fingerprint`, beside the model's vector source).
    var fingerprint: String {
        "photo\(photoBudget) shot\(screenshotBudget) page\(pageBudget)"
    }
}
