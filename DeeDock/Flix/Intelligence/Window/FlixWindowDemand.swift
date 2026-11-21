import Foundation
import UniformTypeIdentifiers

/// What the window in front asks for, in more detail than the slot model's ``FlixWindowIntent``:
/// the items it wants (each with the window's own words), which file types it takes, how large a file
/// may be, and what kind of page it is.
///
/// Produced by Apple Intelligence (``FlixDemandInterpreter``) or, without it, by
/// ``FlixDemandFallbackParser``. Cached per window by ``FlixFitsProvider``.
nonisolated struct FlixWindowDemand: Equatable, Sendable {
    /// One thing the window asks for.
    struct Wanted: Equatable, Sendable {
        /// The window's own words, shown in quotes on the Fits row: "the signed contract".
        var phrase: String
        /// Words to match against names and captions, lowercased: ["signed", "contract"].
        var keywords: [String]
    }

    /// Where the person is, which decides whether folders and apps can fit.
    enum PageKind: String, Equatable, Sendable {
        /// A web form or portal that takes uploads.
        case upload
        /// An email being written.
        case mail
        /// A conversation.
        case chat
        /// A document or canvas that takes pictures and files.
        case document
        case other
    }

    var wanted: [Wanted] = []
    /// Accepted types. Empty accepts anything.
    var acceptedTypes: [UTType] = []
    /// The largest file accepted, in bytes.
    var maximumBytes: Int64?
    var pageKind: PageKind = .other

    /// Whether the window limits what it takes, so drags may need converting.
    var hasLimits: Bool { !acceptedTypes.isEmpty || maximumBytes != nil }

    /// Whether the window asks for anything Flix could suggest.
    var isEmpty: Bool { wanted.isEmpty && !hasLimits }

    /// The slot model's summary.
    var intent: FlixWindowIntent {
        FlixWindowIntent(acceptedTypes: acceptedTypes.map(\.identifier), maximumBytes: maximumBytes,
                         filesOnly: pageKind == .upload)
    }

    /// Types for common extensions and words a page uses ("PDF", "JPG", "Word").
    static func type(named name: String) -> UTType? {
        let word = name.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).lowercased()
        switch word {
        case "": return nil
        case "word": return UTType("org.openxmlformats.wordprocessingml.document")
        case "excel": return UTType("org.openxmlformats.spreadsheetml.sheet")
        case "powerpoint": return UTType("org.openxmlformats.presentationml.presentation")
        case "image", "images", "photo", "photos", "picture", "pictures", "bild", "bilder", "foto", "fotos": return .image
        case "jpg", "jpeg": return .jpeg
        default: return UTType(filenameExtension: word).flatMap { $0.isDynamic ? nil : $0 }
        }
    }

    /// Whether `type` satisfies the accepted types (always true when there are none).
    func accepts(_ type: UTType?) -> Bool {
        guard !acceptedTypes.isEmpty else { return true }
        guard let type else { return false }
        return acceptedTypes.contains { type.conforms(to: $0) }
    }
}
