import Foundation
import UniformTypeIdentifiers

/// What a drag over the Hub would do if it were dropped on the search field (the mockup's `dragTarget`). Pure: the
/// caller reads the drag pasteboard and says which URLs are current results and which files the index holds.
nonisolated enum LookoutPictureDrop: Equatable, Sendable {
    /// A picture file: search with its stored vector when the index holds it, else read it.
    case picture(URL)
    /// A search result, or a document the index holds: Find Similar on it with its stored vector.
    case similar(URL)
    /// Picture bytes with no file (a picture dragged out of a browser): search with them.
    case imageData
    /// A document of a kind Lookout reads that the index doesn't hold: there's nothing to search with ("Lookout hasn't
    /// read this file yet"), and it can't be dropped.
    case unread
    /// Something else (a ZIP file, a folder, an SVG, a result Lookout can't search with): the well says Lookout
    /// searches with pictures only, and it can't be dropped.
    case refused

    /// Whether dropping it on the field searches.
    var isAccepted: Bool {
        switch self {
        case .picture, .similar, .imageData: true
        case .unread, .refused: false
        }
    }

    /// Classifies a drag.
    ///
    /// - Parameters:
    ///   - urls: The dragged file URLs, in order. The first one decides.
    ///   - hasImageData: The pasteboard has picture bytes (PNG, TIFF, JPEG…).
    ///   - fromFilesPane: The drag started in one of the Files tab's own panes: moving files between folders shows no
    ///     well unless the file can be searched with, so it never says "pictures only" in the middle of a move.
    ///   - options: The settings' skipped file types.
    ///   - inIndex: Whether the index holds a file, nil while that isn't known yet.
    ///   - result: Find Similar's availability for a URL that's a current search result, nil for any other URL.
    /// - Returns: Nil when the field has nothing to say about this drag, or can't say yet: a document whose place in
    ///   the index isn't known (`LookoutSimilarAvailability.dependsOnIndex`) waits for the index's answer.
    static func classify(urls: [URL], hasImageData: Bool, fromFilesPane: Bool = false,
                         options: IndexOptions = IndexOptions(), inIndex: (URL) -> Bool? = { _ in nil },
                         result: (URL) -> LookoutSimilarAvailability?) -> LookoutPictureDrop? {
        let drop: LookoutPictureDrop?
        if let url = urls.first {
            if let availability = result(url) {
                drop = availability.isAvailable ? .similar(url) : availability == .notIndexed ? .unread : .refused
            } else {
                let known = inIndex(url)
                switch LookoutSimilarAvailability.of(url, isDirectory: url.hasDirectoryPath, canSearch: true,
                                                     inIndex: known, options: options) {
                case .available(isPicture: true): drop = .picture(url)
                case .available(isPicture: false): drop = known == true ? .similar(url) : nil
                case .notIndexed: drop = .unread
                case .unsupported, .hidden: drop = .refused
                }
            }
        } else {
            drop = hasImageData ? .imageData : nil
        }
        return fromFilesPane && drop?.isAccepted == false ? nil : drop
    }

    /// A file whose type is a picture Lookout reads, by its extension (the drag hasn't been dropped, so the file isn't
    /// read). SVG isn't one (`Rules.isPicture`).
    static func isPictureFile(_ url: URL) -> Bool {
        guard !url.hasDirectoryPath, let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return Rules.isPicture(type)
    }
}
