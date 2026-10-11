import Foundation
import Testing
import UniformTypeIdentifiers
@testable import DeeDock

/// What Lookout indexes, skips and ignores, file by file (`Rules`).
struct LookoutRulesTests {
    private let folder = LookoutTestFolder()
    private let options = IndexOptions()

    private func classify(_ url: URL) -> Rules.Classification {
        Rules.classify(url, type: UTType(filenameExtension: url.pathExtension), options: options)
    }

    @Test func screenshotsAreKnownByTheirAttributeOrTheirName() throws {
        let marked = try folder.write("IMG_0042.png")
        let value = Data([0x62, 0x70, 0x6C, 0x69, 0x73, 0x74])   // any value: the attribute being there is enough
        #expect(value.withUnsafeBytes {
            setxattr(marked.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, $0.count, 0, 0)
        } == 0)
        #expect(classify(marked) == .index(.screenshot))
        #expect(classify(try folder.write("Screenshot 2026-10-01 at 9.41.07 PM.png")) == .index(.screenshot))
        #expect(classify(try folder.write("CleanShot 2026-10-01.png")) == .index(.screenshot))
        #expect(classify(try folder.write("holiday.jpg")) == .index(.image))
    }

    @Test func secretsAreNeverRead() throws {
        for name in ["secret.pem", "server.key", "id_ed25519", "credentials.txt", "keystore.p12", "Secret plans.md"] {
            #expect(classify(try folder.write(name)) == .skip("key or password file"), "\(name)")
        }
    }

    @Test func typeScriptIsCodeAndATransportStreamIsIgnoredVideo() throws {
        let typeScript = try folder.write("app.ts", Data("export const x: number = 1;\n".utf8))
        #expect(classify(typeScript) == .skip("code or data file"))
        var bytes = [UInt8](repeating: 0xFF, count: 188 * 4)
        for packet in 0..<4 { bytes[packet * 188] = 0x47 }
        #expect(classify(try folder.write("clip.ts", Data(bytes))) == .ignore)
    }

    @Test func documentsPDFsAndImagesAreIndexedButNotMediaOrCode() throws {
        for name in ["notes.md", "letter.docx", "page.html", "plain.txt", "report.odt"] {
            #expect(classify(try folder.write(name)) == .index(.doc), "\(name)")
        }
        #expect(classify(try folder.write("scan.pdf")) == .index(.pdf))
        #expect(classify(try folder.write("song.mp3")) == .ignore)
        #expect(classify(try folder.write("movie.mov")) == .ignore)
        #expect(classify(try folder.write("main.swift")) == .skip("code or data file"))
        #expect(classify(try folder.write("data.json")) == .skip("code or data file"))
    }

    @Test func excludedExtensionsAreSkipped() throws {
        var options = IndexOptions()
        options.excludedExtensions = IndexOptions.extensions("HEIC, .txt *.md")
        #expect(options.excludedExtensions == ["heic", "txt", "md"])
        let file = try folder.write("notes.md")
        #expect(Rules.classify(file, type: .init(filenameExtension: "md"), options: options) == .skip("excluded type"))
    }

    @Test func datasetsNeedHundredsOfMachineNamedImages() {
        let frames = (0..<400).map { (folder: "/x/frames", stem: String(format: "frame_%06d", $0), kind: FileKind.image) }
        let photos = (0..<400).map { (folder: "/x/camera", stem: "IMG_\(1000 + $0)", kind: FileKind.image) }
        let few = (0..<50).map { (folder: "/x/few", stem: "clip_\($0)", kind: FileKind.image) }
        let docs = (0..<400).map { (folder: "/x/docs", stem: "doc_\($0)", kind: FileKind.doc) }
        #expect(Rules.datasetFolders(frames + photos + few + docs, roots: []) == ["/x/frames": 400])
        #expect(Rules.datasetFolders(frames, roots: ["/x/frames"]).isEmpty)   // a folder you chose is never a dataset
        #expect(Rules.looksMachineNamed("3f9a1c0e-12ab-4cde"))
        #expect(!Rules.looksMachineNamed("PXL_20260101_123456789"))
    }

    @Test func projectRootsAreMarkedByTheirFiles() throws {
        let repo = try folder.folder("repo")
        try folder.folder("repo/.git")
        let xcode = try folder.folder("app")
        try folder.folder("app/App.xcodeproj")
        let plain = try folder.folder("photos")
        #expect(Rules.isProjectRoot(repo.path))
        #expect(Rules.isProjectRoot(xcode.path))
        #expect(!Rules.isProjectRoot(plain.path))
    }

    @Test func libraryAndDeveloperFoldersAreNotWalked() {
        let home = "/Users/tester"
        func reason(_ path: String, excluded: [String] = []) -> String? {
            Rules.skipReason(forFolder: URL(fileURLWithPath: path), home: home, excluded: excluded)
        }
        #expect(reason("/Users/tester/Library") == "~/Library")
        #expect(reason("/Users/tester/Documents/Library") == nil)
        #expect(reason("/Users/tester/code/node_modules") == "developer folder")
        #expect(reason("/Users/tester/Archive.noindex") == ".noindex folder")
        #expect(reason("/Users/tester/Downloads/Media/x", excluded: ["/Users/tester/Downloads/Media"]) == "excluded folder")
        #expect(reason("/Users/tester/Downloads/MediaKit", excluded: ["/Users/tester/Downloads/Media"]) == nil)
    }

    @Test func theWholeDiskIsNeverARoot() {
        #expect(!Rules.isAllowedRoot("/"))
        #expect(!Rules.isAllowedRoot("//"))
        #expect(!Rules.isAllowedRoot(""))
        #expect(Rules.isAllowedRoot("/Users/tester/Documents"))
    }
}
