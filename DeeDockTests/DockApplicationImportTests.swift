import Foundation
import Testing

/// Bundle fixtures live only in a temporary directory and never request persistent sandbox access.
@MainActor
struct DockApplicationImportTests {
    @Test("Finder validation rejects mixed batches and DeeDock itself before any pin commit")
    func batchValidation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try fixture(at: root, name: "Example", identifier: "fixture.example")
        let document = root.appendingPathComponent("notes.txt")
        try Data("fixture".utf8).write(to: document)
        #expect(throws: (any Error).self) {
            try DockApplicationImporter.read([app, document], excluding: "deedock", bookmark: { _ in Data([1]) })
        }
        #expect(throws: (any Error).self) {
            try DockApplicationImporter.read([app], excluding: "fixture.example", bookmark: { _ in Data([1]) })
        }
        #expect(throws: (any Error).self) {
            try DockApplicationImporter.read([root.appendingPathComponent("Missing.app")], excluding: "deedock", bookmark: { _ in Data([1]) })
        }
    }

    @Test("Finder batches preserve their supplied order and require durable access for every item")
    func orderedImport() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try fixture(at: root, name: "First", identifier: "fixture.first")
        let second = try fixture(at: root, name: "Second", identifier: "fixture.second")
        let imported = try DockApplicationImporter.read([second, first], excluding: "deedock", bookmark: { _ in Data([1, 2]) })
        #expect(imported.map(\.id) == ["fixture.second", "fixture.first"])
        #expect(imported.allSatisfy { $0.bookmarkData == Data([1, 2]) })
        #expect(throws: (any Error).self) {
            try DockApplicationImporter.read([first, second], excluding: "deedock", bookmark: { url in
                if url == second { throw CocoaError(.fileReadNoPermission) }
                return Data([1])
            })
        }
    }

    private func fixture(at root: URL, name: String, identifier: String) throws -> URL {
        let url = root.appendingPathComponent("\(name).app")
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: String] = ["CFBundleIdentifier": identifier, "CFBundleName": name,
                                      "CFBundlePackageType": "APPL", "CFBundleVersion": "1"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return url
    }
}
