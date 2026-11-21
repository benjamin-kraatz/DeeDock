import AppKit
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import DeeDock

/// Automatic upload conversions never leave content out: every frame of a multi-page picture
/// becomes a page, anything the text export cannot show (pictures, headers, footnotes, text boxes,
/// frames) makes the converter decline so the original goes out instead, and Word, OpenDocument,
/// and RTFD files are never converted at all.
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

    @Test func rtfWithPartsTheExportDropsIsDeclined() {
        func parts(_ rtf: String) -> FlixConversionFidelity {
            FlixConversionPlanner.documentParts(in: Data(rtf.utf8), type: .rtf)
        }
        #expect(parts(#"{\rtf1 Hello}"#).isFaithful)
        // Word writes the header and footer distance into every section: that is not a header.
        #expect(parts(#"{\rtf1\sectd\headery708\footery708 Hello}"#).isFaithful)
        // Text that only mentions a control word is escaped and is not one.
        #expect(parts(#"{\rtf1 Type \\footnote to add one}"#).isFaithful)
        for rtf in [
            #"{\rtf1 {\pict\pngblip 89504e47}}"#, #"{\rtf1 {\header Page}}"#, #"{\rtf1 {\footerl Left}}"#,
            #"{\rtf1 Claim{\super\chftn}{\footnote\pard\plain Source.}}"#,
            #"{\rtf1 {\shp{\*\shpinst{\shptxt Box}}}}"#, #"{\rtf1 {\*\do\dobxpage\dptxbx{Box}}}"#,
            #"{\rtf1 \pard\posx1440\posy720\absw2000 Framed\par}"#, #"{\rtf1 \pard\phmrg\pvpara Framed\par}"#,
            #"{\rtf1 {\*\atnid A}{\*\annotation Comment}}"#, #"{\rtf1 {\deleted gone} {\revised new}}"#,
        ] {
            #expect(parts(rtf) == .declined(.unsupportedParts), "\(rtf)")
        }
        // Types that are not converted are never vouched for.
        #expect(FlixConversionPlanner.documentParts(in: Data(), type: .rtfd) == .declined(.unsupportedParts))
        #expect(FlixConversionPlanner.documentParts(in: Data("text".utf8), type: .plainText).isFaithful)
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

    @Test func anRTFDIsNotConvertedAndPlainTextIs() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let text = NSMutableAttributedString(string: "Lease agreement\n")
        let attachment = NSTextAttachment(fileWrapper: FileWrapper(regularFileWithContents: Data("signature".utf8)))
        attachment.fileWrapper?.preferredFilename = "signature.txt"
        text.append(NSAttributedString(attachment: attachment))
        let rtfd = folder.appending(path: "Lease.rtfd")
        let wrapper = try #require(text.rtfdFileWrapper(from: NSRange(location: 0, length: text.length), documentAttributes: [:]))
        try wrapper.write(to: rtfd, options: .atomic, originalContentsURL: nil)
        await #expect(throws: FlixFileConverter.ConversionError.unsupported) {
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

    @Test func anRTFWithAFootnoteIsDeclined() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let rtf = folder.appending(path: "Paper.rtf")
        try Data(#"{\rtf1\ansi Claim{\super\chftn}{\footnote\pard\plain{\super\chftn} Source.}\par}"#.utf8).write(to: rtf)
        await #expect(throws: FlixFileConverter.ConversionError.wouldOmitContent(.unsupportedParts)) {
            _ = try await convert(rtf, type: .rtf, format: .pdf, into: folder)
        }
    }

    @Test func markdownIsLaidOutAsWritten() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let notes = folder.appending(path: "Notes.md")
        try Data("See [the spec](https://example.com/spec) and **this**.".utf8).write(to: notes)
        let markdown = try #require(UTType("net.daringfireball.markdown"))
        let pdf = try await convert(notes, type: markdown, format: .pdf, into: folder)
        // The link's address stays in the copy: Markdown is not interpreted.
        let text = try #require(PDFDocument(url: pdf)?.string)
        #expect(text.contains("https://example.com/spec"))
        #expect(text.contains("**this**"))
    }

    @Test func aWordFileIsRefusedByTheConverterToo() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let docx = try #require(UTType("org.openxmlformats.wordprocessingml.document"))
        let file = folder.appending(path: "Report.docx")
        try Data("PK\u{3}\u{4}word/document.xml".utf8).write(to: file)
        await #expect(throws: FlixFileConverter.ConversionError.unsupported) {
            _ = try await convert(file, type: docx, format: .pdf, into: folder)
        }
    }
}
