import AppKit
import ImageIO
import Testing
@testable import DeeDock

@MainActor
struct ShelfClipboardTests {
    @Test("Literal paths preserve spaces and Unicode and expand only the current user's home")
    func paths() {
        let home = URL(fileURLWithPath: "/Users/example")
        #expect(ShelfClipboardPaths.url("~/Bilder/Grün.png", home: home)?.path == "/Users/example/Bilder/Grün.png")
        #expect(ShelfClipboardPaths.url("/tmp/a b.txt")?.path == "/tmp/a b.txt")
        #expect(ShelfClipboardPaths.url("file:///tmp/a%20b.txt")?.path == "/tmp/a b.txt")
        #expect(ShelfClipboardPaths.url("/tmp/$(touch file).txt")?.path == "/tmp/$(touch file).txt")
        #expect(ShelfClipboardPaths.lines("/tmp/a\r\n/tmp/b\n").map(String.init) == ["/tmp/a", "/tmp/b"])
    }

    @Test("Nonlocal URLs, prose, relative paths and shell expressions are not file paths", arguments: [
        "https://example.com/file.png", "file://remote/tmp/file", "hello world", "relative.txt",
        "$HOME/file", "~another/file", "file:///tmp/a?download=1", "file:///tmp/a#fragment", "/tmp/a\0b"
    ])
    func unsupportedPath(_ text: String) {
        #expect(ShelfClipboardPaths.url(text) == nil)
    }

    @Test("A file's alternate image representation is ignored, while a distinct image is retained")
    func representations() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let file = NSPasteboardItem()
        file.setString("file:///tmp/original.png", forType: .fileURL)
        file.setData(Data([1, 2]), forType: .png)
        file.setString("original.png", forType: .string)
        let image = NSPasteboardItem()
        image.setData(Data([3, 4]), forType: .png)
        image.setData(Data([5, 6]), forType: .tiff)
        pasteboard.writeObjects([file, image])
        #expect(ShelfClipboardReader.canPaste(from: pasteboard))
        #expect(try ShelfClipboardReader.snapshot(from: pasteboard).entries == [
            .file(URL(fileURLWithPath: "/tmp/original.png")), .image(Data([3, 4]))
        ])
    }

    @Test("Paste reads current contents after menu validation and leaves the clipboard unchanged")
    func freshRead() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("/tmp/old", forType: .string)
        #expect(ShelfClipboardReader.canPaste(from: pasteboard))
        pasteboard.clearContents()
        pasteboard.setString("/tmp/new", forType: .string)
        let change = pasteboard.changeCount
        #expect(try ShelfClipboardReader.snapshot(from: pasteboard).entries == [.file(URL(fileURLWithPath: "/tmp/new"))])
        #expect(pasteboard.changeCount == change)
        #expect(pasteboard.string(forType: .string) == "/tmp/new")
        pasteboard.clearContents()
        pasteboard.setString("ordinary prose", forType: .string)
        #expect(!ShelfClipboardReader.canPaste(from: pasteboard))
    }

    @Test("Path batches retain invalid entries for feedback and enforce the entry limit")
    func boundedBatch() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString((["prose"] + (0..<101).map { "/tmp/\($0)" }).joined(separator: "\n"), forType: .string)
        let result = try ShelfClipboardReader.snapshot(from: pasteboard)
        #expect(result.entries.count == 100)
        #expect(result.entries.first == .invalid)
        #expect(result.omitted == 2)
    }

    @Test("Mixed imports keep valid files, suppress duplicates, and report missing paths")
    func mixedFiles() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = fixture.directory.appendingPathComponent("source.txt")
        try Data("source".utf8).write(to: url)
        let importer = ShelfClipboardImporter(shelf: fixture.shelf)
        let failures = await importer.importSnapshot(.init(entries: [
            .file(url), .file(url), .file(fixture.directory.appendingPathComponent("missing")), .invalid
        ]))
        #expect(fixture.shelf.items.map(\.url) == [url.standardizedFileURL])
        #expect(failures.count == 2)
        #expect(try String(contentsOf: url, encoding: .utf8) == "source")
    }

    @Test("Clipboard images survive restart and clearing the Shelf keeps their files")
    func imageLifetime() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let artifacts = ShelfClipboardArtifacts(directory: fixture.directory)
        let importer = ShelfClipboardImporter(shelf: fixture.shelf, artifacts: artifacts)
        let failures = await importer.importSnapshot(.init(entries: [.image(try png())]))
        #expect(failures.isEmpty)
        let url = try #require(fixture.shelf.items.first?.url)
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 2 && image.height == 1)
        #expect(image.alphaInfo != .none)
        fixture.shelf.start()
        #expect(fixture.shelf.items.first?.url == url)
        try fixture.shelf.clear()
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Bookmark failure rolls back only the new image and preserves earlier artifacts")
    func rollback() async throws {
        let fixture = try Fixture(failBookmarks: true)
        defer { fixture.remove() }
        let previous = fixture.directory.appendingPathComponent("keep.png")
        let original = try png()
        try original.write(to: previous)
        let importer = ShelfClipboardImporter(shelf: fixture.shelf,
            artifacts: ShelfClipboardArtifacts(directory: fixture.directory))
        let failures = await importer.importSnapshot(.init(entries: [.image(original)]))
        #expect(!failures.isEmpty)
        #expect(fixture.shelf.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path) == ["keep.png"])
        #expect(try Data(contentsOf: previous) == original)
    }

    @Test("Malformed image data never leaves an artifact")
    func malformedImage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let importer = ShelfClipboardImporter(shelf: fixture.shelf,
            artifacts: ShelfClipboardArtifacts(directory: fixture.directory))
        let failures = await importer.importSnapshot(.init(entries: [.image(Data("broken".utf8))]))
        #expect(!failures.isEmpty)
        #expect(fixture.shelf.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).isEmpty)
    }

    private func png() throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 8, bitsPerPixel: 32))
        bitmap.setColor(.clear, atX: 0, y: 0)
        bitmap.setColor(.red, atX: 1, y: 0)
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    private struct Fixture {
        let directory: URL
        let suite: String
        let defaults: UserDefaults
        let shelf: ShelfController

        init(failBookmarks: Bool = false) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            suite = "ShelfClipboardTests.\(UUID().uuidString)"
            defaults = try #require(UserDefaults(suiteName: suite))
            shelf = ShelfController(repository: ShelfRepository(defaults: defaults), bookmark: {
                if failBookmarks { throw CocoaError(.fileWriteNoPermission) }
                return Data($0.path.utf8)
            })
            shelf.start()
        }

        func remove() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
