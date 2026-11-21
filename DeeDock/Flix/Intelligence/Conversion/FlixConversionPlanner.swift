import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The format a converted copy is written in.
nonisolated enum FlixConversionFormat: String, Codable, Sendable {
    case pdf, jpeg, png

    var fileExtension: String {
        switch self {
        case .pdf: "pdf"
        case .jpeg: "jpg"
        case .png: "png"
        }
    }

    var type: UTType {
        switch self {
        case .pdf: .pdf
        case .jpeg: .jpeg
        case .png: .png
        }
    }

    /// The name the drag label uses: "PDF", "JPEG", "PNG". Format names are not translated.
    var displayName: String { rawValue.uppercased() }
}

/// Whether a converted copy can show everything the original holds.
nonisolated enum FlixConversionFidelity: Equatable, Sendable {
    /// Safe to convert; `pages` is how many pages a picture becomes (0 for text, laid out later).
    case faithful(pages: Int)
    /// The copy would leave something out, so the original is sent instead.
    case declined(Reason)

    enum Reason: Equatable, Sendable {
        /// An animation, which a PDF or a still picture cannot show.
        case animation
        /// Several pages for a format that holds one (JPEG, PNG).
        case multiplePages
        /// More pages than a copy is made for.
        case tooManyPages
        /// Pictures or other attachments the text export does not draw.
        case attachments
        /// Pictures, objects, headers, footers, footnotes, text boxes, frames, comments, or tracked
        /// changes the importer or the text layout drops.
        case unsupportedParts
        case unreadable
    }

    var isFaithful: Bool { if case .faithful = self { true } else { false } }
}

/// How to make one file acceptable to the window in front.
nonisolated struct FlixConversionRecipe: Hashable, Sendable {
    var format: FlixConversionFormat
    /// Shrink pictures until the copy is at most this large.
    var maximumBytes: Int64?
    /// The source is already in `format` and only gets smaller.
    var isResizeOnly = false
}

/// What a drag should do with one item for a window that limits types or sizes.
nonisolated enum FlixConversionDecision: Hashable, Sendable {
    /// The original fits as it is.
    case keep
    case convert(FlixConversionRecipe)
    /// The window would refuse it and Flix cannot convert it (a Pages document for a PDF-only
    /// portal, a PDF over the size limit). It goes out unchanged if dragged, and is not suggested.
    case unconvertible
}

/// Decides conversions from types and sizes alone, without reading any file.
///
/// - Pictures that ImageIO can read (HEIC, PNG, TIFF, WebP, JPEG, GIF…) become a PDF when PDFs are
///   accepted, else a JPEG, else a PNG. A picture over the size limit is scaled down (JPEG, or PNG
///   when only PNG is accepted).
/// - Plain text (Markdown included, laid out as written) and flat RTF become a PDF when PDFs are
///   accepted (``convertibleTextTypes``). Nothing else that holds text is converted.
/// - Word (`.docx`, `.doc`), OpenDocument text, and RTFD are never converted automatically: AppKit's
///   importers silently drop footnotes, endnotes, text boxes, comments, tracked changes, fields, and
///   more, and no check of the file's parts can vouch for all of them. RTFD exists to carry
///   attachments, and its inner RTF is not checked. HTML and web archives are not converted either:
///   their importer needs the main thread and loads external resources (`FlixDocumentImport`).
/// - Everything else is unconvertible: iWork files (Pages, Numbers, Keynote) and other formats
///   need their own app to export, and a PDF or document over the limit cannot be made smaller here.
///
/// The type alone cannot say whether a copy would be faithful, so the converter checks the content
/// before writing one (``picture(frameCount:isAnimated:format:)``, ``text(attachmentCount:)``,
/// ``documentParts(in:type:)``). When a copy would leave something out — a page of a multi-page
/// TIFF, a picture, footnote, or text box in an RTF file, a header — it declines, and the original
/// goes out unchanged: a portal refusing the file is better than one silently receiving less than
/// the person sent.
nonisolated enum FlixConversionPlanner {
    /// The text types Flix Files imports with `NSAttributedString` off the main thread, for the
    /// sensitive scanner and captions. Only ``convertibleTextTypes`` of them are converted.
    static let textTypes: [UTType] = [
        .rtf, .rtfd, .flatRTFD, .plainText,
        UTType("net.daringfireball.markdown"), UTType("org.openxmlformats.wordprocessingml.document"),
        UTType("com.microsoft.word.doc"), UTType("org.oasis-open.opendocument.text"),
    ].compactMap { $0 }

    /// Picture types ImageIO decodes, minus vector and multi-page formats it renders poorly.
    static let imageTypes: Set<String> = {
        let identifiers = (CGImageSourceCopyTypeIdentifiers() as? [String]) ?? []
        return Set(identifiers).subtracting(["com.adobe.pdf", "public.svg-image", "com.adobe.photoshop-image"])
    }()

    static func decision(for item: FlixItem, demand: FlixWindowDemand) -> FlixConversionDecision {
        decision(type: item.contentType ?? item.path.flatMap { UTType(filenameExtension: ($0 as NSString).pathExtension) },
                 byteSize: item.byteSize, isFile: item.path != nil && item.kind != .folder && item.kind != .app,
                 demand: demand)
    }

    static func decision(type: UTType?, byteSize: Int64?, isFile: Bool, demand: FlixWindowDemand) -> FlixConversionDecision {
        guard isFile, demand.hasLimits else { return .keep }
        let accepted = demand.accepts(type)
        let fitsSize = demand.maximumBytes.map { limit in (byteSize ?? 0) <= limit } ?? true
        if accepted && fitsSize { return .keep }
        guard let type else { return .unconvertible }
        let limit = demand.maximumBytes

        if isImage(type) {
            if !accepted {
                if demand.accepts(.pdf) { return .convert(FlixConversionRecipe(format: .pdf, maximumBytes: limit)) }
                if demand.accepts(.jpeg) { return .convert(FlixConversionRecipe(format: .jpeg, maximumBytes: limit)) }
                if demand.accepts(.png) { return .convert(FlixConversionRecipe(format: .png, maximumBytes: limit)) }
                return .unconvertible
            }
            // Accepted but too large: shrink it.
            if demand.accepts(.jpeg) {
                return .convert(FlixConversionRecipe(format: .jpeg, maximumBytes: limit, isResizeOnly: type.conforms(to: .jpeg)))
            }
            if type.conforms(to: .png) { return .convert(FlixConversionRecipe(format: .png, maximumBytes: limit, isResizeOnly: true)) }
            if demand.accepts(.pdf) { return .convert(FlixConversionRecipe(format: .pdf, maximumBytes: limit)) }
            return .unconvertible
        }
        if !accepted, isConvertibleText(type), demand.accepts(.pdf) {
            return .convert(FlixConversionRecipe(format: .pdf, maximumBytes: limit))
        }
        return .unconvertible
    }

    /// The text types converted to a PDF: plain text (which Markdown and source code conform to)
    /// and flat RTF, whose control words ``documentParts(in:type:)`` can check. Word, OpenDocument,
    /// and RTFD are read for scanning and captions but never converted (see the type's notes).
    static let convertibleTextTypes: [UTType] = [.plainText, UTType("net.daringfireball.markdown"), .rtf].compactMap { $0 }

    /// The most pages a multi-page picture (TIFF, multi-image HEIC) becomes; more is declined.
    static let maximumPictureFrames = 30

    /// Whether a converted copy of a picture with `frameCount` frames would show all of it.
    /// - Parameter isAnimated: The frames are an animation (GIF, animated PNG or WebP, HEIC
    ///   sequence), which no PDF or still picture can show.
    static func picture(frameCount: Int, isAnimated: Bool, format: FlixConversionFormat) -> FlixConversionFidelity {
        guard frameCount > 1 else { return frameCount == 1 ? .faithful(pages: 1) : .declined(.unreadable) }
        if isAnimated { return .declined(.animation) }
        guard format == .pdf else { return .declined(.multiplePages) }
        guard frameCount <= maximumPictureFrames else { return .declined(.tooManyPages) }
        return .faithful(pages: frameCount)
    }

    /// Whether the text export keeps everything: attachments (pictures, files, drawings) are not
    /// drawn by the Core Text layout, so a document with any is declined.
    static func text(attachmentCount: Int) -> FlixConversionFidelity {
        attachmentCount == 0 ? .faithful(pages: 0) : .declined(.attachments)
    }

    /// RTF control words for content the importer or the Core Text layout leaves out: pictures
    /// (`\pict`, `\shppict`), embedded objects (`\object`), headers and footers (`\header`,
    /// `\footerl`, …), footnotes and endnotes (`\footnote`), shapes and text boxes (`\shp`,
    /// `\shptxt`, drawing objects `\do` and their text boxes `\dptxbx`), positioned frames and
    /// paragraphs (`\posx…`, `\posy…`, `\posnegx`, `\absw`, `\phmrg`, `\pvpara`, …), comments
    /// (`\annotation`, `\atnid`, `\atrfstart`), and tracked changes (`\revised`, `\deleted`).
    ///
    /// Matched as whole control words (``rtfControlWords(in:)``), so section formatting that Word
    /// writes into every RTF file, such as the header distance `\headery708`, does not count as a
    /// header.
    static let rtfUnsupportedControlWords: Set<String> = [
        "pict", "shppict", "object",
        "header", "headerl", "headerr", "headerf", "footer", "footerl", "footerr", "footerf",
        "footnote",
        "shp", "shpgrp", "shptxt", "do", "dptxbx",
        "posx", "posxc", "posxi", "posxo", "posxl", "posxr", "posy", "posyc", "posyin", "posyout", "posyt",
        "posyb", "posyil", "posnegx", "posnegy", "absw", "absh", "phmrg", "phpg", "phcol", "pvmrg", "pvpg",
        "pvpara", "frame",
        "annotation", "atnid", "atnauthor", "atrfstart", "atrfend",
        "revised", "deleted",
    ]

    /// The control words of an RTF file that are in `words`, read from its raw bytes: a backslash,
    /// then letters, ended by anything else (a numeric parameter, a space, a brace). An escaped
    /// backslash (`\\`) is text, not the start of a word.
    static func rtfControlWords(in data: Data, among words: Set<String> = rtfUnsupportedControlWords) -> Set<String> {
        var found = Set<String>()
        let backslash = UInt8(ascii: "\\")
        func isLetter(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) }
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var index = 0
            while index < bytes.count {
                guard bytes[index] == backslash else { index += 1; continue }
                var end = index + 1
                if end < bytes.count, bytes[end] == backslash { index = end + 1; continue }
                // Control words are at most 32 letters long (the RTF specification's limit).
                while end < bytes.count, end - index <= 32, isLetter(bytes[end]) { end += 1 }
                if end > index + 1, let word = String(bytes: bytes[(index + 1)..<end], encoding: .ascii),
                   words.contains(word) {
                    found.insert(word)
                }
                index = end
            }
        }
        return found
    }

    /// Whether a flat RTF file holds parts the importer or the text export leaves out, from its raw
    /// bytes (``rtfUnsupportedControlWords``). Plain text and Markdown have no such parts. Any other
    /// type is declined: it is not converted (``convertibleTextTypes``), so nothing vouches for it.
    static func documentParts(in data: Data, type: UTType) -> FlixConversionFidelity {
        if type.conforms(to: .rtfd) || type.conforms(to: .flatRTFD) { return .declined(.unsupportedParts) }
        if type.conforms(to: .rtf) {
            return rtfControlWords(in: data).isEmpty ? .faithful(pages: 0) : .declined(.unsupportedParts)
        }
        return isConvertibleText(type) ? .faithful(pages: 0) : .declined(.unsupportedParts)
    }

    static func isImage(_ type: UTType) -> Bool {
        type.conforms(to: .image) && imageTypes.contains { UTType($0).map(type.conforms) ?? false }
    }

    static func isText(_ type: UTType) -> Bool {
        guard !type.conforms(to: .html), !type.conforms(to: .webArchive) else { return false }
        return textTypes.contains { type.conforms(to: $0) }
    }

    /// Text types the converter turns into a PDF: plain text, Markdown, and flat RTF
    /// (``convertibleTextTypes``). Never Word, OpenDocument, RTFD, HTML, or a web archive.
    static func isConvertibleText(_ type: UTType) -> Bool {
        guard isText(type), !type.conforms(to: .rtfd), !type.conforms(to: .flatRTFD) else { return false }
        return convertibleTextTypes.contains { type.conforms(to: $0) }
    }

    /// The copy's file name: the original's name with the new extension ("Scan.heic" → "Scan.pdf").
    static func convertedName(for name: String, format: FlixConversionFormat) -> String {
        let base = (name as NSString).deletingPathExtension
        return (base.isEmpty ? name : base) + "." + format.fileExtension
    }
}
