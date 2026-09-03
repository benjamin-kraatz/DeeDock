import AppKit
import Foundation
import Testing

struct FolderStackTests {
    @Test("V2 applications migrate to typed v3 pins without changing legacy bytes")
    func migration() throws {
        let suite = "FolderStackMigration.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let app = DisplayFixtures.app("legacy")
        let v2 = try JSONEncoder().encode([app])
        defaults.set(v2, forKey: "dock.favorites.v2.display")

        let repository = DisplayProfilesRepository(defaults: defaults)
        #expect(try repository.pins(for: "display") { [] } == [.application(app)])
        #expect(defaults.data(forKey: "dock.favorites.v2.display") == v2)
        #expect(try DockPinsRepository(defaults: defaults, displayID: "display").load() == [.application(app)])
    }

    @Test("Unknown v3 tags fail without overwriting saved bytes")
    func unknownTag() throws {
        let suite = "FolderStackUnknown.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let bytes = Data(#"[{"kind":"future"}]"#.utf8)
        defaults.set(bytes, forKey: "dock.pins.v3.display")
        let repository = DockPinsRepository(defaults: defaults, displayID: "display")
        #expect(throws: (any Error).self) { try repository.load() }
        #expect(defaults.data(forKey: "dock.pins.v3.display") == bytes)
    }

    @Test("Reimporting a folder moves its established UUID, bookmark, and presentation")
    func folderIdentity() {
        let url = URL(fileURLWithPath: "/Fixtures/Projects")
        let existing = FolderReference(id: UUID(), url: url, name: "Projects", bookmarkData: Data([1]), presentation: .list)
        let incoming = FolderReference(id: UUID(), url: url, name: "Renamed", bookmarkData: Data([2]), presentation: .grid)
        let app = DockPin.application(DisplayFixtures.app("app"))
        let result = DockPinEditing.inserting([.folder(incoming)], into: [.folder(existing), app], at: 2)
        #expect(result == [app, .folder(existing)])
    }

    @Test("Folder presentation round-trips per typed pin")
    func presentation() throws {
        let suite = "FolderStackPresentation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = FolderReference(url: URL(fileURLWithPath: "/Fixtures"), name: "Fixtures",
                                     bookmarkData: Data([1]), presentation: .list)
        let repository = DockPinsRepository(defaults: defaults, displayID: "display")
        try repository.save([.folder(folder)])
        #expect(try repository.load() == [.folder(folder)])
    }

    @Test("Finder classification accepts mixed app and folder pins in source order")
    func mixedFinderPins() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Example.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = ["CFBundleIdentifier": "example", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let folder = root.appendingPathComponent("Folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let payload = try DockExternalPayload.read(DocumentResourceAccess([folder, app]), excluding: "deedock",
                                                   bookmark: { _ in Data([1]) })
        #expect(payload.pins.map(\.name) == ["Folder", "Example"])
        #expect(payload.documents == nil)
    }

    @Test("A folder drag reserves generic document feedback for direct app targets")
    func folderDropRouting() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let payload = try DockExternalPayload.read(DocumentResourceAccess([folder]), excluding: "deedock",
                                                   bookmark: { _ in Data([1]) })
        #expect(payload.pins.count == 1)
        #expect(payload.documents != nil)
        #expect(!payload.presentsDocumentFallback)
    }

    @Test("Packages and symbolic links are leaves but cannot become folder pins")
    func nonPinnableFolders() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Folder")
        let package = root.appendingPathComponent("Document.rtfd")
        let link = root.appendingPathComponent("Folder link")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        #expect(try DockPinImporter.kind(of: folder) == .folder)
        #expect(try DockPinImporter.kind(of: package) == .other)
        #expect(try DockPinImporter.kind(of: link) == .other)
    }

    @Test("A failed presentation save restores the previous mode and remains retryable")
    @MainActor func presentationRollback() {
        let folder = FolderReference(url: URL(fileURLWithPath: "/Fixtures"), name: "Fixtures", bookmarkData: Data())
        let state = FolderStackState(folder: folder)
        state.presentationChanged = { _ in false }
        state.choose(.list)
        #expect(state.presentation == .grid)
        #expect(state.error != nil)
    }

    @Test("Folder access releases only a successfully acquired security scope")
    func accessLifetime() {
        let url = URL(fileURLWithPath: "/Fixtures")
        let reference = FolderReference(url: url, name: "Fixtures", bookmarkData: Data())
        var stopped: [URL] = []
        func acquireAndRelease() {
            let access = FolderResourceAccess(reference, startAccess: { _ in true },
                                              stopAccess: { stopped.append($0) })
            withExtendedLifetime(access) {}
        }
        acquireAndRelease()
        #expect(stopped == [url])
    }

    @Test("Folder loading is immediate, hidden-free, name-sorted, and treats packages as leaves")
    func children() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent(".hidden"))
        try Data().write(to: root.appendingPathComponent("item 10.txt"))
        try Data().write(to: root.appendingPathComponent("item 2.txt"))
        let folder = root.appendingPathComponent("Subfolder")
        let package = root.appendingPathComponent("Document.rtfd")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
        let reference = FolderReference(url: root, name: "Root", bookmarkData: Data())
        let access = FolderResourceAccess(reference)
        let entries = try FolderStackLoader.contents(of: access)
        #expect(!entries.contains { $0.name == ".hidden" })
        #expect(entries.firstIndex { $0.name == "item 2.txt" }! < entries.firstIndex { $0.name == "item 10.txt" }!)
        #expect(entries.first { $0.name == "Subfolder" }?.isFolder == true)
        #expect(entries.first { $0.name == "Document.rtfd" }?.isFolder == false)
    }

    @Test("Panel geometry points inward and clamps to negative-origin visible frames", arguments: DockEdge.allCases)
    func geometry(edge: DockEdge) {
        let visible = CGRect(x: -1600, y: -120, width: 1200, height: 800)
        let icon = CGRect(x: -1580, y: 620, width: 48, height: 48)
        let placement = FolderStackGeometry.placement(anchor: FolderStackAnchor(icon: icon, edge: edge, visibleFrame: visible))
        let frame = placement.frame
        #expect(frame.width == 560 && frame.height == 420)
        #expect(frame.minX >= visible.minX + 16 && frame.maxX <= visible.maxX - 16)
        #expect(frame.minY >= visible.minY + 16 && frame.maxY <= visible.maxY - 16)
        let length = edge.isVertical ? frame.height : frame.width
        #expect(placement.chrome.attachment >= 28 && placement.chrome.attachment <= length - 28)
        let dismissed = FolderStackGeometry.dismissedFrame(from: frame, edge: edge)
        switch edge {
        case .bottom: #expect(dismissed.minY < frame.minY)
        case .top: #expect(dismissed.minY > frame.minY)
        case .left: #expect(dismissed.minX < frame.minX)
        case .right: #expect(dismissed.minX > frame.minX)
        }
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
