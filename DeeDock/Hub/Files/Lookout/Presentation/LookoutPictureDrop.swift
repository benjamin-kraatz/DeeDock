import Foundation
import UniformTypeIdentifiers

/// What a drag over the Hub would do if it were dropped on the search field (the mockup's `dragTarget`). Pure: the
/// caller reads the drag pasteboard and says which URLs are current results.
nonisolated enum LookoutPictureDrop: Equatable, Sendable {
    /// A picture file: search with it.
    case picture(URL)
    /// A search result dragged onto the field: Find Similar on it.
    case similar(URL)
    /// Picture bytes with no file (a picture dragged out of a browser): search with them.
    case imageData
    /// Something else (a ZIP file, a folder, a result Lookout can't search with): the well says Lookout searches with
    /// pictures only, and it can't be dropped.
    case refused

    /// Whether dropping it on the field searches.
    var isAccepted: Bool { self != .refused }

    /// Classifies a drag.
    ///
    /// - Parameters:
    ///   - urls: The dragged file URLs, in order. The first one decides.
    ///   - hasImageData: The pasteboard has picture bytes (PNG, TIFF, JPEG…).
    ///   - fromFilesPane: The drag started in one of the Files tab's own panes: moving files between folders shows no
    ///     well unless it's a picture, so it never says "pictures only" in the middle of a move.
    ///   - result: Find Similar's availability for a URL that's a current search result, nil for any other URL.
    /// - Returns: Nil when the field has nothing to say about this drag.
    static func classify(urls: [URL], hasImageData: Bool, fromFilesPane: Bool = false,
                         result: (URL) -> LookoutSimilarAvailability?) -> LookoutPictureDrop? {
        let drop: LookoutPictureDrop?
        if let url = urls.first {
            if let availability = result(url) {
                drop = availability.isAvailable ? .similar(url) : .refused
            } else if isPictureFile(url) {
                drop = .picture(url)
            } else {
                drop = .refused
            }
        } else {
            drop = hasImageData ? .imageData : nil
        }
        return fromFilesPane && drop == .refused ? nil : drop
    }

    /// A file whose type is a picture, by its extension (the drag hasn't been dropped, so the file isn't read).
    static func isPictureFile(_ url: URL) -> Bool {
        guard !url.hasDirectoryPath, let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }
}
