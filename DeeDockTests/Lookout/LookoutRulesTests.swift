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

    /// Told apart by name only: no file is opened to classify it (a FIFO would block, a link would be followed).
    @Test func typeScriptNamesAreCodeAndM2TSIsIgnoredVideo() throws {
        var bytes = [UInt8](repeating: 0xFF, count: 188 * 4)
        for packet in 0..<4 { bytes[packet * 188] = 0x47 }   // a real transport stream: still not read
        #expect(classify(try folder.write("app.ts", Data("export const x: number = 1;\n".utf8))) == .skip("code or data file"))
        #expect(classify(try folder.write("clip.ts", Data(bytes))) == .skip("code or data file"))
        #expect(classify(try folder.write("module.mts", Data(bytes))) == .skip("code or data file"))
        #expect(classify(try folder.write("00001.m2ts", Data(bytes))) == .ignore)
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

    @Test("Folders Lookout never reads are refused as roots", arguments: [
        ("/", Rules.RootRefusal.wholeDisk), ("//", .wholeDisk), ("", .wholeDisk), ("/Volumes", .wholeDisk),
        ("/Users/tester", .homeFolder), ("/Users/tester/", .homeFolder), ("/Users", .homeFolder),
        ("/Users/tester/Library", .library), ("/Users/tester/Library/CloudStorage", .library),
        ("/Users/tester/Library/Mobile Documents", .library),
        ("/Users/tester/Library/Mobile Documents/com~apple~TextEdit", .library),
        ("/Users/tester/Library/Containers/com.example.app", .library),
        ("/Users/tester/.ssh", .hidden), ("/Users/tester/Code/.git/objects", .hidden),
        ("/Volumes/Archive/.Trashes", .hidden),
        ("/System/Library", .system), ("/Library/Keychains", .system), ("/Applications", .system),
        ("/usr/local/share", .system), ("/private/etc", .system), ("/private/var/db", .system),
        ("/private/var/folders/aa/bb/C/com.example", .system), ("/private/var/folders/aa/bb/T", .system),
        ("/dev", .system), ("/cores", .system),
    ])
    func refusedRoots(path: String, refusal: Rules.RootRefusal) {
        #expect(Rules.rootRefusal(path, home: "/Users/tester", temporary: "/private/var/folders/aa/bb/T") == refusal)
    }

    @Test("Ordinary folders, other drives, scratch folders, iCloud Drive and cloud storage may be roots", arguments: [
        "/Users/tester/Documents", "/Users/tester/Library Books", "/Users/Shared/Photos", "/Volumes/Archive",
        "/Volumes/Archive/Scans", "/private/tmp/scratch", "/private/var/folders/aa/bb/T/LookoutTests-1",
        "/Users/tester/Library/CloudStorage/Dropbox", "/Users/tester/Library/CloudStorage/GoogleDrive-me@example.com/My Drive",
        "/Users/tester/Library/CloudStorage/OneDrive-Personal", "/Users/tester/Library/Mobile Documents/com~apple~CloudDocs",
        "/Users/tester/Library/Mobile Documents/com~apple~CloudDocs/Taxes",
    ])
    func allowedRoots(path: String) {
        #expect(Rules.rootRefusal(path, home: "/Users/tester", temporary: "/private/var/folders/aa/bb/T") == nil)
    }

    @Test func aFolderInsideABundleIsRefused() throws {
        let folder = LookoutTestFolder()
        let contents = try folder.folder("Tool.app/Contents/Resources")
        #expect(Rules.rootRefusal(contents.path, home: "/Users/tester") == .bundle)
        #expect(Rules.rootRefusal(folder.path, home: "/Users/tester") == nil)
    }

    @Test func rootsAreCheckedAsGivenAndWhereTheyLead() throws {
        let folder = LookoutTestFolder()
        let library = try folder.folder("home/Library/Keychains")
        let documents = try folder.folder("home/Documents")
        let link = folder.url.appendingPathComponent("home/Notes")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: library)
        let checked = Rules.checkRoots([link.path, documents.path + "/", folder.path + "/home"],
                                       home: folder.path + "/home")
        #expect(checked.allowed == [documents.path])
        #expect(checked.refused.map(\.refusal) == [.library, .homeFolder])
    }
}
