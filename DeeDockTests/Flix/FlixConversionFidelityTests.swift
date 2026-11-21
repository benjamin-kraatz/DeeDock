import AppKit
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import DeeDock

/// Automatic upload conversions never leave content out: every frame of a multi-page picture
/// becomes a page, and anything the text export cannot show (attachments, pictures, headers) makes
/// the converter decline so the original goes out instead.
@Suite(.serialized)
struct FlixConversionFidelityTests {
    // MARK: Planner rules

    @Test func multiPagePicturesBecomeOnePDFPagePerFrame() {
        #expect(FlixConversionPlanner.picture(frameCount: 1, isAnimated: false, format: .jpeg) == .faithful(pages: 1))
        #expect(FlixConversionPlanner.picture(frameCount: 3, isAnimated: false, format: .pdf) == .faithful(pages: 3))
        // A single-picture format cannot hold several pages, and an animation fits no format.
        #expect(FlixConversionPlanner.picture(frameCount: 3, isAnimated: false, format: .jpeg) == .declined(.multiplePages))
        #expect(FlixConversionPlanner.picture(frameCount: 3, isAnimated: false, format: .png) == .declined(.multiplePages))
        #expect(FlixConversionPlanner.picture(frameCount: 12, isAnimated: true, format: .pdf) == .declined(.animation))
        let tooMany = FlixConversionPlanner.maximumPictureFrames + 1
        #expect(FlixConversionPlanner.picture(frameCount: tooMany, isAnimated: false, format: .pdf) == .declined(.tooManyPages))
        #expect(FlixConversionPlanner.picture(frameCount: 0, isAnimated: false, format: .pdf) == .declined(.unreadable))
    }

    @Test func textWithAttachmentsIsDeclined() {
        #expect(FlixConversionPlanner.text(attachmentCount: 0).isFaithful)
        #expect(FlixConversionPlanner.text(attachmentCount: 1) == .declined(.attachments))
    }

    @Test func documentsWithPartsTheExportDropsAreDeclined() throws {
        let docx = try #require(UTType("org.openxmlformats.wordprocessingml.document"))
        let odt = try #require(UTType("org.oasis-open.opendocument.text"))
        func bytes(_ text: String) -> Data { Data(("PK\u{3}\u{4}" + text).utf8) }
        #expect(FlixConversionPlanner.documentParts(in: bytes("word/document.xml word/styles.xml"), type: docx).isFaithful)
        for part in ["word/media/image1.png", "word/header1.xml", "word/footer2.xml", "word/charts/chart1.xml",
                     "word/embeddings/oleObject1.bin", "word/comments.xml"] {
            #expect(FlixConversionPlanner.documentParts(in: bytes("word/document.xml " + part), type: docx)
                    == .declined(.unsupportedParts))
        }
        #expect(FlixConversionPlanner.documentParts(in: bytes("content.xml Pictures/1.png"), type: odt)
                == .declined(.unsupportedParts))
        #expect(FlixConversionPlanner.documentParts(in: Data(#"{\rtf1 Hello}"#.utf8), type: .rtf).isFaithful)
        #expect(FlixConversionPlanner.documentParts(in: Data(#"{\rtf1 {\pict\pngblip 89504e47}}"#.utf8), type: .rtf)
                == .declined(.unsupportedParts))
        #expect(FlixConversionPlanner.documentParts(in: Data(#"{\rtf1 {\header Page}}"#.utf8), type: .rtf)
                == .declined(.unsupportedParts))
    }

    @Test func legacyWordFilesAreNotConverted() throws {
        let doc = try #require(UTType("com.microsoft.word.doc"))
        let demand = FlixWindowDemand(acceptedTypes: [.pdf])
        #expect(FlixConversionPlanner.decision(type: doc, byteSize: 1_000, isFile: true, demand: demand) == .unconvertible)
        // Still read for scanning and captions.
        #expect(FlixConversionPlanner.isText(doc))
    }

    // MARK: The converter

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appending(path: "FlixFidelity-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Nothing in the temporary folder is protected under this home.
    private let policy = FlixReadPolicy(home: "/FlixFidelityHome", allowedRoots: [])

    private func image(_ color: CGColor) -> CGImage {
        let context = CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        return context.makeImage()!
    }

    private func writeImage(frames: Int, type: UTType, to url: URL) throws {
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, frames, nil))
        for index in 0..<frames {
            CGImageDestinationAddImage(destination, image(CGColor(red: CGFloat(index) / 3, green: 0.4, blue: 0.6, alpha: 1)), nil)
        }
        #expect(CGImageDestinationFinalize(destination))
    }

    private func convert(_ url: URL, type: UTType, format: FlixConversionFormat, into folder: URL) async throws -> URL {
        try await FlixFileConverter.convert(url.path, policy: policy, type: type, recipe: FlixConversionRecipe(format: format),
                                            name: url.lastPathComponent, into: folder.appending(path: "out")).url
    }

    @Test func aMultiPageTIFFKeepsEveryPage() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let tiff = folder.appending(path: "Scan.tiff")
        try writeImage(frames: 3, type: .tiff, to: tiff)
        let pdf = try await convert(tiff, type: .tiff, format: .pdf, into: folder)
        #expect(PDFDocument(url: pdf)?.pageCount == 3)
        // As a JPEG two of the pages would vanish, so the original is kept instead.
        await #expect(throws: FlixFileConverter.ConversionError.wouldOmitContent(.multiplePages)) {
            _ = try await convert(tiff, type: .tiff, format: .jpeg, into: folder)
        }
    }

    @Test func anAnimationIsNotFlattened() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let gif = folder.appending(path: "Loop.gif")
        try writeImage(frames: 2, type: .gif, to: gif)
        await #expect(throws: FlixFileConverter.ConversionError.wouldOmitContent(.animation)) {
            _ = try await convert(gif, type: .gif, format: .pdf, into: folder)
        }
    }

    @Test func anRTFDWithAPictureIsDeclinedAndPlainTextConverts() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let text = NSMutableAttributedString(string: "Lease agreement\n")
        let attachment = NSTextAttachment(fileWrapper: FileWrapper(regularFileWithContents: Data("signature".utf8)))
        attachment.fileWrapper?.preferredFilename = "signature.txt"
        text.append(NSAttributedString(attachment: attachment))
        let rtfd = folder.appending(path: "Lease.rtfd")
        let wrapper = try #require(text.rtfdFileWrapper(from: NSRange(location: 0, length: text.length), documentAttributes: [:]))
        try wrapper.write(to: rtfd, options: .atomic, originalContentsURL: nil)
        await #expect(throws: FlixFileConverter.ConversionError.wouldOmitContent(.attachments)) {
            _ = try await convert(rtfd, type: .rtfd, format: .pdf, into: folder)
        }

        let notes = folder.appending(path: "Notes.txt")
        try Data("Plain notes".utf8).write(to: notes)
        let pdf = try await convert(notes, type: .plainText, format: .pdf, into: folder)
        #expect(PDFDocument(url: pdf)?.pageCount == 1)
    }

    @Test func anRTFWithAPictureIsDeclined() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let rtf = folder.appending(path: "Memo.rtf")
        try Data(#"{\rtf1\ansi Memo {\pict\pngblip 89504e470d0a1a0a}}"#.utf8).write(to: rtf)
        await #expect(throws: FlixFileConverter.ConversionError.wouldOmitContent(.unsupportedParts)) {
            _ = try await convert(rtf, type: .rtf, format: .pdf, into: folder)
        }
    }
}
