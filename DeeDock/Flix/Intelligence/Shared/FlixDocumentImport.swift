import AppKit
import UniformTypeIdentifiers

/// Reads text documents through AppKit's importers safely off the main actor: RTF, RTFD, Word
/// (`.docx`, `.doc`), and OpenDocument text.
///
/// The importer is always told the document type, so it never sniffs a file into HTML or a web
/// archive: those importers run WebKit, need the main thread, and load a page's external images,
/// style sheets, and frames from the network. HTML and web archives are therefore never read here
/// (and never converted or scanned by Flix Files). Files above ``maximumBytes`` are not read. Every
/// read goes through ``FlixSafeFile``, never a path, so a link swapped in after the read policy's
/// check is not followed.
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

    /// The document in `file` as attributed text, or nil when its type is not imported, it is too
    /// large, or it cannot be read.
    ///
    /// Flat documents (RTF, flat RTFD, Word, OpenDocument) are decoded from the descriptor's bytes,
    /// so the importer reads exactly the file the read policy checked. An RTFD package is a folder:
    /// its contents are listed first without following links, and a package holding a link, or
    /// larger than ``maximumBytes`` in total, is not read; the importer then reads the checked path.
    static func attributedString(_ file: FlixSafeFile, type: UTType) -> NSAttributedString? {
        guard let documentType = documentType(for: type) else { return nil }
        if file.isDirectory {
            guard documentType == .rtfd, packageIsPlain(file.url) else { return nil }
            guard let wrapper = try? FileWrapper(url: file.url, options: .immediate) else { return nil }
            return NSAttributedString(rtfdFileWrapper: wrapper, documentAttributes: nil)
        }
        guard let data = file.mapped(maximumBytes: maximumBytes) else { return nil }
        return try? NSAttributedString(data: data, options: [.documentType: documentType], documentAttributes: nil)
    }

    /// Whether a package holds only plain files and folders, no links, and at most ``maximumBytes``.
    private static func packageIsPlain(_ url: URL) -> Bool {
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys,
                                                              options: [], errorHandler: { _, _ in false })
        else { return false }
        var total: Int64 = 0
        var count = 0
        for case let child as URL in enumerator {
            count += 1
            guard count <= 2_000, let values = try? child.resourceValues(forKeys: Set(keys)),
                  values.isSymbolicLink != true, values.isRegularFile == true || values.isDirectory == true
            else { return false }
            total += Int64(values.fileSize ?? 0)
            guard total <= maximumBytes else { return false }
        }
        return true
    }
}
