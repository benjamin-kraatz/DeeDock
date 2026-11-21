import AppKit
import UniformTypeIdentifiers

/// Reads text documents through AppKit's importers safely off the main actor: RTF, RTFD, Word
/// (`.docx`, `.doc`), and OpenDocument text.
///
/// The importer is always told the document type, so it never sniffs a file into HTML or a web
/// archive: those importers run WebKit, need the main thread, and load a page's external images,
/// style sheets, and frames from the network. HTML and web archives are therefore never read here
/// (and never converted or scanned by Flix Files). Files above ``maximumBytes`` are not read.
nonisolated enum FlixDocumentImport {
    /// The largest document opened for its text.
    static let maximumBytes: Int64 = 25_000_000

    /// The importer's document type for `type`, or nil when Flix Files does not import it.
    static func documentType(for type: UTType) -> NSAttributedString.DocumentType? {
        if type.conforms(to: .html) || type.conforms(to: .webArchive) { return nil }
        if type.conforms(to: .rtfd) || type.conforms(to: .flatRTFD) { return .rtfd }
        if type.conforms(to: .rtf) { return .rtf }
        if let docx = UTType("org.openxmlformats.wordprocessingml.document"), type.conforms(to: docx) { return .officeOpenXML }
        if let doc = UTType("com.microsoft.word.doc"), type.conforms(to: doc) { return .docFormat }
        if let odt = UTType("org.oasis-open.opendocument.text"), type.conforms(to: odt) { return .openDocument }
        return nil
    }

    /// The document at `url` as attributed text, or nil when its type is not imported, it is too
    /// large, or it cannot be read.
    static func attributedString(at url: URL, type: UTType, byteSize: Int64? = nil) -> NSAttributedString? {
        guard let documentType = documentType(for: type) else { return nil }
        let size = byteSize ?? (try? url.resourceValues(forKeys: [.totalFileSizeKey, .fileSizeKey]))
            .flatMap { $0.totalFileSize ?? $0.fileSize }.map(Int64.init) ?? 0
        guard size <= maximumBytes else { return nil }
        return try? NSAttributedString(url: url, options: [.documentType: documentType], documentAttributes: nil)
    }
}
