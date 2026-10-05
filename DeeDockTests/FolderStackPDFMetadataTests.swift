import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import DeeDock

/// Page counts must follow PDFKit's lock rule. An owner-password file (empty user password)
/// stays readable. A user-password file does not. Fixtures are generated in a temp directory.
struct FolderStackPDFMetadataTests {
    @Test("Plain, owner-password, user-password, and unreadable PDFs match PDFKit lock state")
    func pageCountMatchesPDFKitLockState() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderStackPDF-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let plain = root.appendingPathComponent("plain.pdf")
        try writePDF(pageCount: 3, to: plain)
        let plainDocument = try #require(PDFDocument(url: plain))
        #expect(!plainDocument.isEncrypted)
        #expect(!plainDocument.isLocked)
        #expect(plainDocument.pageCount == 3)
        #expect(await FolderStackMediaReader.metadata(for: reference(plain)) == .pdf(pageCount: 3))

        let ownerOnly = root.appendingPathComponent("owner.pdf")
        try writeEncryptedPDF(pageCount: 2, to: ownerOnly, userPassword: "", ownerPassword: "owner-secret")
        let ownerDocument = try #require(PDFDocument(url: ownerOnly))
        #expect(ownerDocument.isEncrypted)
        #expect(!ownerDocument.isLocked)
        #expect(ownerDocument.pageCount == 2)
        #expect(await FolderStackMediaReader.metadata(for: reference(ownerOnly)) == .pdf(pageCount: 2))

        let userLocked = root.appendingPathComponent("user.pdf")
        try writeEncryptedPDF(pageCount: 2, to: userLocked, userPassword: "user-secret", ownerPassword: "owner-secret")
        let lockedDocument = try #require(PDFDocument(url: userLocked))
        #expect(lockedDocument.isEncrypted)
        #expect(lockedDocument.isLocked)
        #expect(await FolderStackMediaReader.metadata(for: reference(userLocked)) == nil)

        let unreadable = root.appendingPathComponent("broken.pdf")
        try Data("not a pdf".utf8).write(to: unreadable)
        #expect(PDFDocument(url: unreadable) == nil)
        #expect(await FolderStackMediaReader.metadata(for: reference(unreadable)) == nil)
    }

    private func reference(_ url: URL) -> FolderStackEntryReference {
        FolderStackEntryReference(url: url, name: url.lastPathComponent, isFolder: false,
                                  contentType: "com.adobe.pdf")
    }

    /// Writes a small uncompressed PDF. The page count lives in the page tree, which is what the reader consults.
    private func writePDF(pageCount: Int, to url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 72, height: 72)
        let consumer = try #require(CGDataConsumer(url: url as CFURL))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        for _ in 0..<pageCount {
            context.beginPDFPage(nil)
            context.endPDFPage()
        }
        context.closePDF()
    }

    /// PDFKit is only the fixture writer. CoreGraphics cannot encrypt a PDF, and the reader must not use PDFKit.
    private func writeEncryptedPDF(pageCount: Int, to url: URL, userPassword: String, ownerPassword: String) throws {
        let document = PDFDocument()
        for _ in 0..<pageCount {
            document.insert(PDFPage(), at: document.pageCount)
        }
        let wrote = document.write(to: url, withOptions: [
            .userPasswordOption: userPassword,
            .ownerPasswordOption: ownerPassword,
        ])
        try #require(wrote)
    }
}
