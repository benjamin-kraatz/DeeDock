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
/// - Text documents that `NSAttributedString` reads (RTF, RTFD, plain text, Markdown, HTML, Word
///   `.docx`/`.doc`, OpenDocument text) become a PDF when PDFs are accepted.
/// - Everything else is unconvertible: iWork files (Pages, Numbers, Keynote) and other formats
///   need their own app to export, and a PDF or document over the limit cannot be made smaller here.
nonisolated enum FlixConversionPlanner {
    /// The text types `NSAttributedString` can import.
    static let textTypes: [UTType] = [
        .rtf, .rtfd, .flatRTFD, .plainText, .html, .webArchive,
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
        if !accepted, isText(type), demand.accepts(.pdf) {
            return .convert(FlixConversionRecipe(format: .pdf, maximumBytes: limit))
        }
        return .unconvertible
    }

    static func isImage(_ type: UTType) -> Bool {
        type.conforms(to: .image) && imageTypes.contains { UTType($0).map(type.conforms) ?? false }
    }

    static func isText(_ type: UTType) -> Bool {
        textTypes.contains { type.conforms(to: $0) }
    }

    /// The copy's file name: the original's name with the new extension ("Scan.heic" → "Scan.pdf").
    static func convertedName(for name: String, format: FlixConversionFormat) -> String {
        let base = (name as NSString).deletingPathExtension
        return (base.isEmpty ? name : base) + "." + format.fileExtension
    }
}
