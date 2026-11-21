import AppKit
import CoreText
import Darwin

/// A generated document's words.
struct CorpusDocument {
    let title: String
    let text: String
}

/// Writes a `CorpusDocument` in one of the corpus formats, the way the real thing would be stored: a text PDF with
/// pages, a scan (an image-only PDF, no text layer), Word, RTF, plain text, Markdown, or a screenshot of the document
/// open in a window (marked the way macOS marks screenshots).
enum CorpusRenderer {
    static func render(_ document: CorpusDocument, as format: CorpusSpec.Format, to url: URL) throws {
        switch format {
        case .pdf: try textPDF(document, to: url)
        case .scan: try scanPDF(document, to: url)
        case .docx: try attributed(document, type: .officeOpenXML, to: url)
        case .rtf: try attributed(document, type: .rtf, to: url)
        case .txt: try "\(document.title)\n\n\(document.text)\n".write(to: url, atomically: true, encoding: .utf8)
        case .md: try "# \(document.title)\n\n\(document.text)\n".write(to: url, atomically: true, encoding: .utf8)
        case .screenshot: try screenshot(document, to: url)
        }
    }

    private static let page = CGRect(x: 0, y: 0, width: 595, height: 842)   // A4 in points
    private static let margin: CGFloat = 64

    private static func styled(_ document: CorpusDocument, size: CGFloat = 12) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 8
        let text = NSMutableAttributedString(string: document.title + "\n", attributes: [
            .font: NSFont.boldSystemFont(ofSize: size * 1.6), .paragraphStyle: paragraph,
        ])
        text.append(NSAttributedString(string: document.text, attributes: [
            .font: NSFont.systemFont(ofSize: size), .paragraphStyle: paragraph,
        ]))
        return text
    }

    /// A text PDF: the document laid out on as many A4 pages as it needs.
    private static func textPDF(_ document: CorpusDocument, to url: URL) throws {
        var box = page
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw BenchFailure("can't write \(url.path)") }
        let framesetter = CTFramesetterCreateWithAttributedString(styled(document))
        var start = 0
        let length = styled(document).length
        repeat {
            context.beginPDFPage(nil)
            let path = CGPath(rect: page.insetBy(dx: margin, dy: margin), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: start, length: 0), path, nil)
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            context.endPDFPage()
            guard visible.length > 0 else { break }
            start += visible.length
        } while start < length
        context.closePDF()
    }

    /// A scan: the page rendered to a slightly grey bitmap and placed in a PDF as an image, with no text layer.
    private static func scanPDF(_ document: CorpusDocument, to url: URL) throws {
        let scale: CGFloat = 2
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(page.width * scale),
                                            pixelsHigh: Int(page.height * scale), bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw BenchFailure("can't render \(url.path)")
        }
        NSGraphicsContext.saveGraphicsState()
        let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.current = graphics
        let context = graphics.cgContext
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(NSColor(white: 0.96, alpha: 1).cgColor)
        context.fill(page)
        let framesetter = CTFramesetterCreateWithAttributedString(styled(document, size: 11))
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(), CGPath(rect: page.insetBy(dx: margin, dy: margin),
                                                                             transform: nil), nil)
        CTFrameDraw(frame, context)
        NSGraphicsContext.restoreGraphicsState()
        guard let image = bitmap.cgImage else { throw BenchFailure("can't render \(url.path)") }

        var box = page
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { throw BenchFailure("can't write \(url.path)") }
        pdf.beginPDFPage(nil)
        pdf.draw(image, in: page)
        pdf.endPDFPage()
        pdf.closePDF()
    }

    private static func attributed(_ document: CorpusDocument, type: NSAttributedString.DocumentType, to url: URL) throws {
        let text = styled(document)
        try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: type])
            .write(to: url)
    }

    /// The document open in a window on a desktop, saved as a PNG with the screen-capture attribute.
    private static func screenshot(_ document: CorpusDocument, to url: URL) throws {
        let size = CGSize(width: 1440, height: 900)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width),
                                            pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4,
                                            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0) else {
            throw BenchFailure("can't render \(url.path)")
        }
        NSGraphicsContext.saveGraphicsState()
        let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.current = graphics
        NSColor(calibratedRed: 0.32, green: 0.42, blue: 0.58, alpha: 1).setFill()
        CGRect(origin: .zero, size: size).fill()
        let window = CGRect(x: 160, y: 50, width: 1120, height: 800)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: window, xRadius: 12, yRadius: 12).fill()
        NSColor(white: 0.92, alpha: 1).setFill()
        CGRect(x: window.minX, y: window.maxY - 40, width: window.width, height: 40).fill()
        (document.title as NSString).draw(at: CGPoint(x: window.minX + 90, y: window.maxY - 28), withAttributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: NSColor.secondaryLabelColor,
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(styled(document, size: 16))
        let body = CGRect(x: window.minX + 60, y: window.minY + 30, width: window.width - 120, height: window.height - 100)
        CTFrameDraw(CTFramesetterCreateFrame(framesetter, CFRange(), CGPath(rect: body, transform: nil), nil),
                    graphics.cgContext)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw BenchFailure("can't render \(url.path)")
        }
        try png.write(to: url)
        // The value Spotlight reads ("1" works, as DigUp's testbed writes it).
        let value = "1"
        guard setxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", value, value.utf8.count, 0, 0) == 0 else {
            throw BenchFailure("can't mark \(url.path) as a screenshot")
        }
    }
}
