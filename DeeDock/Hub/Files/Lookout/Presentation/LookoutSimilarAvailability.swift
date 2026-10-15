import Foundation
import UniformTypeIdentifiers

/// Whether Find Similar is offered for a file, as the preview column's button, the context menu, ⌘⇧L, the search
/// field's drop well and the Apps tab's file actions show it. Pure, so the rules are testable.
nonisolated enum LookoutSimilarAvailability: Equatable, Sendable {
    /// Not offered: a folder, or Lookout isn't set up or can't search.
    case hidden
    /// Shown but disabled: Lookout doesn't read this kind of file ("Lookout doesn't read this kind of file").
    case unsupported
    /// Shown but disabled: a document of a kind Lookout reads that the index doesn't hold, so there's nothing to
    /// search with ("Lookout hasn't read this file yet"). It's outside the chosen folders, or still waiting.
    case notIndexed
    /// Offered. `isPicture`: the file is a picture, which can be read like a dropped one when the index doesn't
    /// hold it.
    case available(isPicture: Bool)

    var isAvailable: Bool {
        if case .available = self { true } else { false }
    }

    /// Why it's shown disabled, or nil when it isn't.
    var disabledReason: LocalizedStringResource? {
        switch self {
        case .unsupported: .lookoutSimilarUnsupported
        case .notIndexed: .lookoutSimilarNotIndexed
        case .hidden, .available: nil
        }
    }

    /// The availability for one file.
    ///
    /// - Parameters:
    ///   - url: The file.
    ///   - isDirectory: Folders never have Find Similar. A package that is one document (an `.rtfd`) isn't a folder
    ///     here, whatever the caller says.
    ///   - canSearch: Lookout is set up and can search (ready, reading files, or paused).
    ///   - inIndex: Whether the index holds a vector for the file, when that's known. A document Lookout reads but
    ///     hasn't read (outside the chosen folders, or still waiting) has nothing to search with; a picture can
    ///     still be read. Unknown counts as held until the index answers.
    ///   - options: The settings' skipped file types, which Lookout doesn't read either.
    static func of(_ url: URL, isDirectory: Bool, canSearch: Bool, inIndex: Bool?,
                   options: IndexOptions = IndexOptions()) -> LookoutSimilarAvailability {
        guard canSearch, !isDirectory || Rules.packageDocumentEntry(url) != nil else { return .hidden }
        switch Rules.classify(url, type: UTType(filenameExtension: url.pathExtension), options: options) {
        case .index(.image), .index(.screenshot):
            return .available(isPicture: true)
        case .index:
            return inIndex == false ? .notIndexed : .available(isPicture: false)
        case .skip, .ignore:
            return .unsupported
        }
    }

    /// Whether `of` needs the index's answer for `url`: a document of a kind Lookout reads, which it can search with
    /// only when the index holds it. Pictures never wait for it, and other files don't depend on it.
    static func dependsOnIndex(_ url: URL, isDirectory: Bool, options: IndexOptions = IndexOptions()) -> Bool {
        of(url, isDirectory: isDirectory, canSearch: true, inIndex: nil, options: options) == .available(isPicture: false)
    }
}
