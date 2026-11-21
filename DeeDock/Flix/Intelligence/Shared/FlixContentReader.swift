import AppKit
import CoreServices
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

/// What Flix Files read from one file for captions, facts, and Ask Robi. Bounded: at most
/// ``FlixContentReader/textLimit`` characters by default, one downscaled picture.
nonisolated struct FlixFileContent: @unchecked Sendable {
    // `@unchecked`: the CGImage is immutable and only handed from the reader to one model call.
    var text = ""
    /// Images and screenshots: the picture, at most ``FlixContentReader/pictureSide`` pixels long.
    var image: CGImage?
    /// Pages of a PDF or document, slides of a presentation, from the file or Spotlight's metadata.
    var pageCount: Int?
    var isPresentation = false
    var isSpreadsheet = false
}

/// The file's modification date and size, which together decide whether a cached analysis is
/// still current.
nonisolated struct FlixFileStamp: Codable, Equatable, Sendable {
    var modified: Date?
    var size: Int64?
}

/// Reads bounded text and pictures from files, off the main actor.
///
/// Only call it for paths `FlixReadPolicy.canRead` allows: reading a protected folder DOKK was not
/// granted would make macOS ask. Every method checks for cancellation between steps, reads at most
/// the first pages of a PDF and the first 64 KB of a text file, and never loads a whole large file.
nonisolated enum FlixContentReader {
    /// The most text one file contributes to a caption or facts.
    static let textLimit = 6_000
    /// Longest side of a picture handed to a model.
    static let pictureSide = 1_024
    /// PDF pages read for text.
    static let pdfPages = 4

    /// The modification date and size of each path that exists.
    @concurrent static func stamps(_ paths: [String]) async -> [String: FlixFileStamp] {
        var stamps: [String: FlixFileStamp] = [:]
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .totalFileSizeKey]
        for path in paths {
            guard !Task.isCancelled else { break }
            guard let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: keys) else { continue }
            stamps[path] = FlixFileStamp(modified: values.contentModificationDate,
                                         size: (values.fileSize ?? values.totalFileSize).map(Int64.init))
        }
        return stamps
    }

    /// The names in `folder`, for picking a rename that doesn't collide. Empty when unreadable.
    @concurrent static func names(in folder: String) async -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [])
    }

    /// Reads `path`. Returns nil when it is gone or unreadable.
    ///
    /// - Parameters:
    ///   - limit: The most text to return.
    ///   - wantsPicture: Load a downscaled picture for images and screenshots.
    ///   - recognizesText: Run Vision text recognition on that picture (when no model reads images,
    ///     or for Ask Robi). The first recognition in a process loads Vision's models and is slow.
    @concurrent static func read(path: String, kind: FlixItemKind, contentType: String?, limit: Int = textLimit,
                                 wantsPicture: Bool, recognizesText: Bool) async -> FlixFileContent? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.isReadableFile(atPath: path) else { return nil }
        let type = contentType.flatMap(UTType.init) ?? UTType(filenameExtension: url.pathExtension)
        var content = FlixFileContent()
        content.isPresentation = type?.conforms(to: .presentation) == true
        content.isSpreadsheet = type?.conforms(to: .spreadsheet) == true
        if kind == .image || kind == .screenshot || type?.conforms(to: .image) == true {
            guard wantsPicture || recognizesText, let image = picture(at: url) else { return content }
            if wantsPicture { content.image = image }
            if recognizesText, !Task.isCancelled { content.text = String(await recognizeText(image).prefix(limit)) }
            return content
        }
        if type?.conforms(to: .pdf) == true {
            readPDF(url, limit: limit, into: &content)
        } else if let type, type.conforms(to: .plainText) || type.conforms(to: .sourceCode) || type.conforms(to: .json)
                    || type.conforms(to: .commaSeparatedText) || type.conforms(to: .xml) {
            content.text = plainText(url, limit: limit)
        } else if let type, type.conforms(to: .rtf) || type.conforms(to: .rtfd)
                    || ["docx", "doc", "odt"].contains(url.pathExtension.lowercased()) {
            // Office and RTF documents through AppKit's importers. HTML is left out: its importer
            // loads WebKit, which belongs on the main thread.
            if let text = try? NSAttributedString(url: url, options: [:], documentAttributes: nil).string {
                content.text = String(text.prefix(limit))
            }
        }
        if content.pageCount == nil { content.pageCount = spotlightPageCount(path) }
        return content
    }

    private static func readPDF(_ url: URL, limit: Int, into content: inout FlixFileContent) {
        guard let document = PDFDocument(url: url) else { return }
        content.pageCount = document.pageCount
        var text = ""
        for index in 0..<min(document.pageCount, pdfPages) {
            guard !Task.isCancelled, text.count < limit else { break }
            if let page = document.page(at: index)?.string { text += page + "\n" }
        }
        content.text = String(text.prefix(limit))
    }

    private static func plainText(_ url: URL, limit: Int) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 64 * 1_024)) ?? Data()
        return String(String(decoding: data, as: UTF8.self).prefix(limit))
    }

    /// A downscaled picture, decoded through ImageIO's thumbnail path so a 50-megapixel photo never
    /// decodes at full size.
    static func picture(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pictureSide,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Text Vision recognizes in a picture, lines joined.
    static func recognizeText(_ image: CGImage) async -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        guard let observations = try? await request.perform(on: image) else { return "" }
        return observations.map(\.transcript).joined(separator: "\n")
    }

    /// `kMDItemNumberOfPages`: pages of documents and slides of presentations, as Spotlight indexed
    /// them. Spotlight's own metadata; the file is not opened.
    private static func spotlightPageCount(_ path: String) -> Int? {
        guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString),
              let value = MDItemCopyAttribute(item, kMDItemNumberOfPages) as? NSNumber else { return nil }
        return value.intValue > 0 ? value.intValue : nil
    }
}
