import Foundation
import UniformTypeIdentifiers

/// Whether Find Similar is offered for a file, as the preview column's button, the context menu and ⌘⇧L show it.
/// Pure, so the rules are testable.
nonisolated enum LookoutSimilarAvailability: Equatable, Sendable {
    /// Not offered: a folder, Lookout isn't set up or can't search, or a document the index doesn't hold.
    case hidden
    /// Shown but disabled: Lookout doesn't read this kind of file ("Lookout doesn't read this kind of file").
    case unsupported
    /// Offered. `isPicture`: the file is a picture, which can be read like a dropped one when the index doesn't
    /// hold it.
    case available(isPicture: Bool)

    var isAvailable: Bool {
        if case .available = self { true } else { false }
    }

    /// The availability for one file.
    ///
    /// - Parameters:
    ///   - url: The file.
    ///   - isDirectory: Folders never have Find Similar.
    ///   - canSearch: Lookout is set up and can search (ready, reading files, or paused).
    ///   - inIndex: Whether the index holds a vector for the file, when that's known. A document Lookout reads but
    ///     hasn't read yet (outside the chosen folders, or still waiting) has nothing to search with; a picture can
    ///     still be read.
    ///   - options: The settings' skipped file types, which Lookout doesn't read either.
    static func of(_ url: URL, isDirectory: Bool, canSearch: Bool, inIndex: Bool?,
                   options: IndexOptions = IndexOptions()) -> LookoutSimilarAvailability {
        guard canSearch, !isDirectory else { return .hidden }
        switch Rules.classify(url, type: UTType(filenameExtension: url.pathExtension), options: options) {
        case .index(.image), .index(.screenshot):
            return .available(isPicture: true)
        case .index:
            return inIndex == false ? .hidden : .available(isPicture: false)
        case .skip, .ignore:
            return .unsupported
        }
    }
}
