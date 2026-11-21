import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// Writes converted copies of files for an upload: pictures to PDF, JPEG, or PNG (scaled down to a
/// size limit), and text documents to PDF.
///
/// Runs off the main actor, except HTML import, which AppKit requires on the main thread (and which
/// is limited to small files). Text documents are laid out with Core Text on A4 pages with 54-point
/// margins; images embedded in RTFD or Word files are not drawn. The original is never changed.
nonisolated enum FlixFileConverter {
    enum ConversionError: Error {
        case unreadable
        case unsupported
        case tooLarge
    }

    /// The longest side a converted picture keeps before any size limit applies.
    static let maximumPixels: CGFloat = 4_096
    /// HTML is imported on the main thread, so only small pages are converted.
    static let maximumHTMLBytes = 1_500_000

    /// Converts `source` into `folder`, named after `name` with the new extension.
    /// - Returns: The copy's URL and its size in bytes.
    @concurrent static func convert(_ source: URL, type: UTType, recipe: FlixConversionRecipe, name: String,
                        into folder: URL) async throws -> (url: URL, bytes: Int64) {
        try Task.checkCancellation()
        let data: Data
        if FlixConversionPlanner.isImage(type) {
            data = try imageData(source, recipe: recipe)
        } else if FlixConversionPlanner.isText(type), recipe.format == .pdf {
            let text = try await attributedText(source, type: type)
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

    private static func imageData(_ source: URL, recipe: FlixConversionRecipe) throws -> Data {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else { throw ConversionError.unreadable }
        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? CGFloat) ?? maximumPixels
        let height = (properties?[kCGImagePropertyPixelHeight] as? CGFloat) ?? maximumPixels
        let longest = min(maximumPixels, max(width, height))
        // A PDF wrapper costs a few kilobytes on top of the JPEG inside it.
        let budget = recipe.maximumBytes.map { recipe.format == .pdf ? max(0, $0 - 16_000) : $0 }
        let scales: [CGFloat] = [1, 0.8, 0.64, 0.5, 0.4, 0.32, 0.25, 0.18]
        let qualities: [CGFloat] = recipe.format == .png ? [1] : [0.85, 0.72, 0.6, 0.5]
        var smallest: (data: Data, image: CGImage)?
        for scale in scales {
            guard let image = thumbnail(imageSource, longestSide: max(64, longest * scale)) else { continue }
            for quality in qualities {
                guard let data = encode(image, as: recipe.format == .png ? .png : .jpeg, quality: quality) else { continue }
                if smallest == nil || data.count < smallest!.data.count { smallest = (data, image) }
                if budget.map({ Int64(data.count) <= $0 }) ?? true {
                    return recipe.format == .pdf ? try pdf(wrappingJPEG: data, size: image) : data
                }
            }
        }
        guard let smallest else { throw ConversionError.unreadable }
        // Nothing reached the limit; hand over the smallest copy rather than the original.
        return recipe.format == .pdf ? try pdf(wrappingJPEG: smallest.data, size: smallest.image) : smallest.data
    }

    private static func thumbnail(_ source: CGImageSource, longestSide: CGFloat) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(longestSide),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func encode(_ image: CGImage, as type: UTType, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        // The image is a fresh thumbnail, so the copy carries no metadata: no location, no camera.
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// One page the picture's shape, longest side 842 points (A4's height). The JPEG passes through
    /// unchanged, so the PDF is barely larger than the picture.
    private static func pdf(wrappingJPEG jpeg: Data, size image: CGImage) throws -> Data {
        guard let provider = CGDataProvider(data: jpeg as CFData),
              let embedded = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true,
                                     intent: .defaultIntent) else { throw ConversionError.unreadable }
        let aspect = CGFloat(image.width) / CGFloat(max(1, image.height))
        let page = aspect >= 1 ? CGSize(width: 842, height: 842 / aspect) : CGSize(width: 842 * aspect, height: 842)
        let output = NSMutableData()
        var box = CGRect(origin: .zero, size: page)
        guard let consumer = CGDataConsumer(data: output), let context = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { throw ConversionError.unreadable }
        context.beginPDFPage(nil)
        context.draw(embedded, in: box)
        context.endPDFPage()
        context.closePDF()
        return output as Data
    }

    // MARK: Text

    private static func attributedText(_ source: URL, type: UTType) async throws -> NSAttributedString {
        if type.conforms(to: .html) {
            let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= maximumHTMLBytes else { throw ConversionError.tooLarge }
            // AppKit's HTML importer must run on the main thread. It hands back RTF data, which is
            // Sendable, and the layout happens here again.
            let rtf = try await MainActor.run { () throws -> Data in
                let html = try NSAttributedString(url: source, options: [.documentType: NSAttributedString.DocumentType.html],
                                                  documentAttributes: nil)
                return try html.data(from: NSRange(location: 0, length: html.length),
                                     documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            }
            return try NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                          documentAttributes: nil)
        }
        if let markdown = UTType("net.daringfireball.markdown"), type.conforms(to: markdown) {
            return try markdownText(source)
        }
        if type.conforms(to: .plainText) {
            let string = try String(contentsOf: source, encoding: .utf8)
            return NSAttributedString(string: string, attributes: [.font: bodyFont])
        }
        return try NSAttributedString(url: source, options: [:], documentAttributes: nil)
    }

    /// Markdown's inline styles (bold, italic, code) become fonts; block syntax such as headings
    /// stays as written.
    private static func markdownText(_ source: URL) throws -> NSAttributedString {
        let string = try String(contentsOf: source, encoding: .utf8)
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
