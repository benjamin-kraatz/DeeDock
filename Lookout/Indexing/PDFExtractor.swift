// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

import AppKit
import CoreGraphics
import Foundation
import PDFKit

/// Reads a PDF a range of pages at a time: pages with real text become text, scans and slides become pictures.
nonisolated enum PDFExtractor {
    struct Page: Sendable {
        let number: Int        // 1-based
        let text: String       // may be empty for scans
        let imagePath: String? // set when the page had too little text and was rendered for the vision encoder
        var ocr = false        // the text came from OCR: the text layer was garbled (`PageTextProblem.lostLetters`)
        /// Text read in glyph order (`PageTextProblem.glyphOrder`): too garbled to show or match words against, but
        /// enough of its words survive for a meaning vector beside the page's picture.
        var garbled: String?
    }

    /// Reads the pages in `range(pageCount)` (0-based). Pages with real text become text; scans and slides are
    /// rendered. Text layers PDFKit reads garbled are replaced: by OCR where letters were lost (Arabic ligatures), by
    /// the rendered page where the words came out in glyph order (Bengali, which OCR can't read). On the multilingual
    /// eval (2026-10-08), a glyph-order page as picture + garbled-text vector beat the picture alone: R@1 0.75 vs 0.73,
    /// MRR 0.84 vs 0.81 (an English query for a Bengali page found it only through the text vector).
    ///
    /// - Throws: `ExtractError.unreadable` or `.locked`; a page image that can't be written.
    static func pages(of url: URL, range: (Int) -> Range<Int>, minText: Int, renderPixels: Int, to folder: URL)
        throws -> (pages: [Page], total: Int, title: String?) {
        guard let document = PDFDocument(url: url) else { throw ExtractError.unreadable("can't open PDF") }
        if document.isLocked { throw ExtractError.locked }
        var pages: [Page] = []
        for index in range(document.pageCount).clamped(to: 0..<document.pageCount) {
            guard let page = document.page(at: index) else { continue }
            var text = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            var garbled: String?
            switch PageTextProblem.check(text) {
            case .lostLetters:
                // OCR's reading replaces the text layer only when it's real Arabic; otherwise the layer stays as it is.
                if ScreenshotOCR.readsArabic, let image = render(page, pixels: 2000) {
                    let read = ScreenshotOCR.text(in: image).trimmingCharacters(in: .whitespacesAndNewlines)
                    if read.count >= minText, PageTextProblem.check(read) == nil,
                       read.unicodeScalars.contains(where: { SearchText.Script.arabic.contains($0.value) }) {
                        pages.append(Page(number: index + 1, text: read, imagePath: nil, ocr: true))
                        continue
                    }
                }
                if text.count >= minText {
                    pages.append(Page(number: index + 1, text: text, imagePath: nil))
                    continue
                }
            case .glyphOrder:
                (text, garbled) = ("", text)
            case nil:
                if text.count >= minText {
                    pages.append(Page(number: index + 1, text: text, imagePath: nil))
                    continue
                }
            }
            guard let image = render(page, pixels: renderPixels) else { continue }
            let out = folder.appendingPathComponent(UUID().uuidString + ".png")
            try ImageExtractor.write(image, to: out, png: true)
            pages.append(Page(number: index + 1, text: text, imagePath: out.path, garbled: garbled))
        }
        let title = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
        return (pages, document.pageCount, title)
    }

    /// The page as a picture, fitted into a square of `pixels`.
    static func render(_ page: PDFPage, pixels: Int) -> CGImage? {
        let side = CGFloat(pixels)
        return page.thumbnail(of: NSSize(width: side, height: side), for: .mediaBox)
            .cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
