// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

import AppKit
import Foundation

/// Reads documents' text and cuts it into pieces for the model.
nonisolated enum DocExtractor {
    /// The text of a document. rtf (and an rtfd's `TXT.rtf`, which `QueuedFileGate` read), docx, doc and odt go
    /// through the Cocoa text system; everything else is plain or markup text, HTML, a web archive, subtitles or LaTeX
    /// (`DocumentText`). Cocoa's HTML import runs WebKit and must be on the main thread, and the service indexes on a
    /// background queue, so HTML never goes through it.
    ///
    /// - Parameters:
    ///   - data: The file's bytes, read from the descriptor `QueuedFileGate` checked.
    ///   - fileExtension: The file's extension, which says how to read it.
    /// - Throws: The file can't be decoded.
    static func text(of data: Data, fileExtension: String) throws -> String {
        if let text = try DocumentText.text(of: data, fileExtension: fileExtension) { return text }
        let type: NSAttributedString.DocumentType
        switch fileExtension.lowercased() {
        case "docx": type = .officeOpenXML
        case "doc": type = .docFormat
        case "odt": type = .openDocument
        default: type = .rtf   // rtf, and the rtf inside an rtfd
        }
        return try NSAttributedString(data: data, options: [.documentType: type], documentAttributes: nil).string
    }

    /// Splits text into ~`size`-character pieces (~450 tokens) that overlap a little, breaking at whitespace. The cut
    /// is the same every time, so a later step of a long document goes on where the last one stopped.
    static func chunks(_ text: String, size: Int = 1800, overlap: Int = 200, limit: Int) -> [String] {
        let clean = text
            .replacingOccurrences(of: #"[ \t\u{00A0}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n\s*\n\s*\n+"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var chunks: [String] = []
        var start = clean.startIndex
        while start < clean.endIndex, chunks.count < limit {
            var end = clean.index(start, offsetBy: size, limitedBy: clean.endIndex) ?? clean.endIndex
            if end < clean.endIndex, let space = clean[start..<end].lastIndex(where: \.isWhitespace),
               clean.distance(from: start, to: space) > size / 2 {
                end = space
            }
            let chunk = clean[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty { chunks.append(chunk) }
            guard end < clean.endIndex else { break }
            var next = clean.index(end, offsetBy: -overlap, limitedBy: start) ?? end
            if next <= start { next = end }
            // Start the next chunk on a word boundary.
            while next < end, !clean[next].isWhitespace { next = clean.index(after: next) }
            start = next < end ? next : end
        }
        return chunks
    }
}
