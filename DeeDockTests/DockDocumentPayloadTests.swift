import Foundation
import Synchronization
import Testing

struct DockDocumentPayloadTests {
    @Test("Files, folders, and packages retain their original URLs and batch order")
    func documents() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("notes.txt")
        try Data("notes".utf8).write(to: file)
        let folder = root.appendingPathComponent("Project")
        let package = root.appendingPathComponent("Report.rtfd")
        for url in [folder, package] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) }
        let access = DocumentResourceAccess([folder, file, package, file])
        let payload = try DockExternalPayload.read(access, excluding: "deedock")
        #expect(payload.documents === access)
        #expect(payload.documents?.urls == [folder, file, package])
        #expect(payload.pins.isEmpty)
        try DockExternalPayload.validateDocuments(access.urls)
    }

    @Test("Applications remain pin payloads; mixed and malformed batches open nothing")
    func applications() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Example.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = ["CFBundleIdentifier": "example", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let payload = try DockExternalPayload.read(DocumentResourceAccess([app]), excluding: "deedock", bookmark: { _ in Data([1]) })
        #expect(payload.pins.map(\.id) == ["example"])
        #expect(payload.documents == nil)
        let file = root.appendingPathComponent("notes.txt")
        try Data().write(to: file)
        for urls in [[app, file], [root.appendingPathComponent("Missing")], [URL(string: "https://example.com")!], []] {
            #expect(throws: (any Error).self) { try DockExternalPayload.read(DocumentResourceAccess(urls), excluding: "deedock", bookmark: { _ in Data() }) }
        }
        #expect(throws: (any Error).self) { try DockExternalPayload.validateDocuments([app]) }
        #expect(throws: (any Error).self) { try DockExternalPayload.read(DocumentResourceAccess([app]), excluding: "example", bookmark: { _ in Data() }) }
        try FileManager.default.removeItem(at: file)
        #expect(throws: (any Error).self) { try DockExternalPayload.validateDocuments([file]) }
    }

    @Test("Shared access stops exactly the successful acquisitions, after the last owner releases it")
    func accessOwnership() {
        let stopped = Mutex<[URL]>([])
        let first = URL(fileURLWithPath: "/fixture/one")
        let second = URL(fileURLWithPath: "/fixture/two")
        var access: DocumentResourceAccess? = DocumentResourceAccess([first, second, first], startAccess: { $0 == first }, stopAccess: { url in
            stopped.withLock { $0.append(url) }
        })
        weak var weakAccess = access
        var acceptedRequest = access
        #expect(acceptedRequest?.urls == [first, second])
        access = nil
        #expect(weakAccess != nil && stopped.withLock { $0.isEmpty })
        acceptedRequest = nil
        #expect(weakAccess == nil)
        #expect(stopped.withLock { $0 } == [first])
        weakAccess = nil
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
