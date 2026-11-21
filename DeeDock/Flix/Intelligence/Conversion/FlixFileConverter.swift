import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// Writes converted copies of files for an upload: pictures to PDF, JPEG, or PNG (scaled down to a
/// size limit), and text documents to PDF.
///
/// Runs entirely off the main actor (`@concurrent`) and is bounded: pictures decode through
/// ImageIO's thumbnail path at most ``maximumPixels`` long, plain text and Markdown are read only up
/// to ``maximumTextBytes``, documents only up to `FlixDocumentImport.maximumBytes`, and a text over
/// ``maximumCharacters`` is refused rather than laid out on thousands of pages. HTML and web
/// archives are never converted: AppKit's HTML importer needs the main thread and loads a page's
/// external resources (`FlixDocumentImport`). Text documents are laid out with Core Text on A4
/// pages with 54-point margins. The original is never changed, and is opened through
/// ``FlixSafeFile`` so a link swapped in after the conversion was queued is never followed.
///
/// A copy is written only when it shows everything the original does (`FlixConversionFidelity`):
/// a multi-page TIFF or multi-image HEIC becomes one PDF page per frame (up to
/// `FlixConversionPlanner.maximumPictureFrames`), and the converter declines
/// (``ConversionError/wouldOmitContent``) an animation, several frames for JPEG or PNG, and a text
/// document with pictures, attachments, embedded objects, headers, or footers the text layout would
/// drop. A declined file goes out unchanged.
nonisolated enum FlixFileConverter {
    enum ConversionError: Error, Equatable {
        case unreadable
        case unsupported
        case tooLarge
        /// The copy would leave out part of the original (see the type's notes).
        case wouldOmitContent(FlixConversionFidelity.Reason)
    }

    /// The longest side a converted picture keeps before any size limit applies.
    static let maximumPixels: CGFloat = 4_096
    /// The largest plain-text or Markdown file converted.
    static let maximumTextBytes: Int64 = 4_000_000
    /// The longest text laid out as a PDF.
    static let maximumCharacters = 2_000_000
    /// The largest picture read for a conversion.
    static let maximumPictureBytes: Int64 = 200_000_000

    /// Converts the file at `path` into `folder`, named after `name` with the new extension.
    /// - Returns: The copy's URL and its size in bytes.
    /// - Throws: ``ConversionError``; `wouldOmitContent` when a faithful copy is not possible.
    @concurrent static func convert(_ path: String, policy: FlixReadPolicy, type: UTType, recipe: FlixConversionRecipe,
                                    name: String, into folder: URL) async throws -> (url: URL, bytes: Int64) {
        try Task.checkCancellation()
        guard let file = FlixSafeFile.open(path, policy: policy) else { throw ConversionError.unreadable }
        let data: Data
        if FlixConversionPlanner.isImage(type) {
            data = try imageData(file, type: type, recipe: recipe)
        } else if FlixConversionPlanner.isConvertibleText(type), recipe.format == .pdf {
            let text = try attributedText(file, type: type)
            guard text.length <= maximumCharacters else { throw ConversionError.tooLarge }
            try Task.checkCancellation()
            data = try pdf(from: text)
        } else {
            throw ConversionError.unsupported
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appending(path: FlixConversionPlanner.convertedName(for: name, format: recipe.format))
        try data.write(to: target, options: .atomic)
        return (target, Int64(data.count))
    }

    // MARK: Pictures

    private static func imageData(_ file: FlixSafeFile, type: UTType, recipe: FlixConversionRecipe) throws -> Data {
        guard let bytes = file.mapped(maximumBytes: maximumPictureBytes),
              let imageSource = CGImageSourceCreateWithData(bytes as CFData, nil) else { throw ConversionError.unreadable }
        let frames = CGImageSourceGetCount(imageSource)
        switch FlixConversionPlanner.picture(frameCount: frames, isAnimated: isAnimation(imageSource, type: type, frames: frames),
                                             format: recipe.format) {
        case .declined(let reason): throw ConversionError.wouldOmitContent(reason)
        case .faithful(let pages) where pages > 1:
            // A PDF wrapper costs a few kilobytes per page on top of the JPEGs inside it.
            let budget = recipe.maximumBytes.map { max(0, $0 - 16_000 * Int64(pages)) / Int64(pages) }
            let encoded = try (0..<pages).map { index in
                try Task.checkCancellation()
                return try jpegFrame(imageSource, index: index, budget: budget)
            }
            return try pdf(wrappingJPEGs: encoded)
        case .faithful:
            break
        }
        // A PDF wrapper costs a few kilobytes on top of the JPEG inside it.
        let budget = recipe.maximumBytes.map { recipe.format == .pdf ? max(0, $0 - 16_000) : $0 }
        let encoded = try frame(imageSource, index: 0, as: recipe.format == .png ? .png : .jpeg, budget: budget)
        return recipe.format == .pdf ? try pdf(wrappingJPEGs: [encoded]) : encoded.data
    }

    /// Whether a source's frames are an animation rather than pages.
    private static func isAnimation(_ source: CGImageSource, type: UTType, frames: Int) -> Bool {
        guard frames > 1 else { return false }
        if type.conforms(to: .gif) { return true }
        let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any] ?? [:]
        if properties[kCGImagePropertyHEICSDictionary] != nil || properties[kCGImagePropertyWebPDictionary] != nil {
            return true
        }
        if let png = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any], png[kCGImagePropertyAPNGLoopCount] != nil {
            return true
        }
        // Animated PNG and WebP files with several frames are animations even without the keys.
        return type.conforms(to: .png) || type.identifier == "org.webmproject.webp"
    }

    private static func jpegFrame(_ source: CGImageSource, index: Int, budget: Int64?) throws -> (data: Data, image: CGImage) {
        try frame(source, index: index, as: .jpeg, budget: budget)
    }

    /// One frame encoded at the largest scale and quality that fits `budget`, else the smallest
    /// encoding tried, rather than the original.
    private static func frame(_ source: CGImageSource, index: Int, as format: UTType,
                              budget: Int64?) throws -> (data: Data, image: CGImage) {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? CGFloat) ?? maximumPixels
        let height = (properties?[kCGImagePropertyPixelHeight] as? CGFloat) ?? maximumPixels
        let longest = min(maximumPixels, max(width, height))
        let scales: [CGFloat] = [1, 0.8, 0.64, 0.5, 0.4, 0.32, 0.25, 0.18]
        let qualities: [CGFloat] = format == .png ? [1] : [0.85, 0.72, 0.6, 0.5]
        var smallest: (data: Data, image: CGImage)?
        for scale in scales {
            guard let image = thumbnail(source, index: index, longestSide: max(64, longest * scale)) else { continue }
            for quality in qualities {
                guard let data = encode(image, as: format, quality: quality) else { continue }
                if smallest == nil || data.count < smallest!.data.count { smallest = (data, image) }
                if budget.map({ Int64(data.count) <= $0 }) ?? true { return (data, image) }
            }
        }
        guard let smallest else { throw ConversionError.unreadable }
        return smallest
    }

    private static func thumbnail(_ source: CGImageSource, index: Int, longestSide: CGFloat) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            // The size comes from the file's own metadata, so it is bounded before conversion.
            kCGImageSourceThumbnailMaxPixelSize: FlixNumbers.int(longestSide, in: 1...Int(maximumPixels)) ?? Int(maximumPixels),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
    }

    private static func encode(_ image: CGImage, as type: UTType, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        // The image is a fresh thumbnail, so the copy carries no metadata: no location, no camera.
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// One page per picture, each the picture's shape, longest side 842 points (A4's height). The
    /// JPEGs pass through unchanged, so the PDF is barely larger than the pictures.
    private static func pdf(wrappingJPEGs pictures: [(data: Data, image: CGImage)]) throws -> Data {
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output), let context = CGContext(consumer: consumer, mediaBox: nil, nil)
        else { throw ConversionError.unreadable }
        for picture in pictures {
            guard let provider = CGDataProvider(data: picture.data as CFData),
                  let embedded = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true,
                                         intent: .defaultIntent) else { throw ConversionError.unreadable }
            let aspect = CGFloat(picture.image.width) / CGFloat(max(1, picture.image.height))
            let size = aspect >= 1 ? CGSize(width: 842, height: 842 / aspect) : CGSize(width: 842 * aspect, height: 842)
            var box = CGRect(origin: .zero, size: size)
            let pageInfo = [kCGPDFContextMediaBox as String: Data(bytes: &box, count: MemoryLayout<CGRect>.size)] as CFDictionary
            context.beginPDFPage(pageInfo)
            context.draw(embedded, in: box)
            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }

    // MARK: Text

    /// The document as attributed text, once it is known that the text layout keeps all of it.
    private static func attributedText(_ file: FlixSafeFile, type: UTType) throws -> NSAttributedString {
        // Never HTML or a web archive, even when the planner was handed one (see the type's notes).
        if type.conforms(to: .html) || type.conforms(to: .webArchive) { throw ConversionError.unsupported }
        if let markdown = UTType("net.daringfireball.markdown"), type.conforms(to: markdown) {
            return try markdownText(boundedText(file))
        }
        if type.conforms(to: .plainText) {
            return NSAttributedString(string: try boundedText(file), attributes: [.font: bodyFont])
        }
        if !file.isDirectory, let bytes = file.mapped(maximumBytes: FlixDocumentImport.maximumBytes),
           case .declined(let reason) = FlixConversionPlanner.documentParts(in: bytes, type: type) {
            throw ConversionError.wouldOmitContent(reason)
        }
        guard let text = FlixDocumentImport.attributedString(file, type: type) else { throw ConversionError.unreadable }
        var attachments = 0
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if value != nil { attachments += 1 }
        }
        if case .declined(let reason) = FlixConversionPlanner.text(attachmentCount: attachments) {
            throw ConversionError.wouldOmitContent(reason)
        }
        return text
    }

    /// A UTF-8 text file, refused above ``maximumTextBytes``.
    private static func boundedText(_ file: FlixSafeFile) throws -> String {
        guard file.size <= maximumTextBytes else { throw ConversionError.tooLarge }
        return String(decoding: file.read(upTo: Int(maximumTextBytes)), as: UTF8.self)
    }

    /// Markdown's inline styles (bold, italic, code) become fonts; block syntax such as headings
    /// stays as written.
    private static func markdownText(_ string: String) throws -> NSAttributedString {
        let parsed = (try? AttributedString(markdown: string, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(string)
        let output = NSMutableAttributedString()
        for run in parsed.runs {
            let text = String(parsed[run.range].characters)
            var font = bodyFont
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.code) {
                    font = CTFontCreateUIFontForLanguage(.userFixedPitch, 10.5, nil) ?? bodyFont
                } else {
                    var traits: CTFontSymbolicTraits = []
                    if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
                    if intent.contains(.emphasized) { traits.insert(.traitItalic) }
                    if !traits.isEmpty { font = CTFontCreateCopyWithSymbolicTraits(bodyFont, 0, nil, traits, traits) ?? bodyFont }
                }
            }
            output.append(NSAttributedString(string: text, attributes: [.font: font]))
        }
        return output
    }

    private static var bodyFont: CTFont {
        CTFontCreateUIFontForLanguage(.system, 11, nil) ?? CTFontCreateWithName("Helvetica" as CFString, 11, nil)
    }

    /// Lays `text` out on A4 pages. AppKit colours become Core Text colours, which is the only
    /// attribute Core Text reads under a different key.
    private static func pdf(from text: NSAttributedString) throws -> Data {
        let string = NSMutableAttributedString(attributedString: text)
        let full = NSRange(location: 0, length: string.length)
        string.enumerateAttribute(.foregroundColor, in: full) { value, range, _ in
            if let color = value as? NSColor {
                string.addAttribute(NSAttributedString.Key(kCTForegroundColorAttributeName as String), value: color.cgColor, range: range)
            }
        }
        string.enumerateAttribute(.font, in: full) { value, range, _ in
            if value == nil { string.addAttribute(.font, value: bodyFont, range: range) }
        }
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        var page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let textRect = page.insetBy(dx: 54, dy: 54)
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output), let context = CGContext(consumer: consumer, mediaBox: &page, nil)
        else { throw ConversionError.unreadable }
        var location = 0
        repeat {
            context.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), CGPath(rect: textRect, transform: nil), nil)
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            context.endPDFPage()
            guard visible.length > 0 else { break }
            location += visible.length
        } while location < string.length
        context.closePDF()
        return output as Data
    }
}
