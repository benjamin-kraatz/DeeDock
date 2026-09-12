import Foundation
import Testing
@testable import DeeDock

@MainActor
struct ShelfCompostTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(age: TimeInterval = 0) -> ShelfItem {
        let id = UUID()
        return ShelfItem(id: id, url: URL(fileURLWithPath: "/CompostTests/\(id).txt"),
                         name: "\(id).txt", bookmarkData: Data([1, 2, 3]),
                         addedAt: now.addingTimeInterval(-age))
    }

    private func withShelf(_ document: ShelfDocument,
                           body: (ShelfController, ShelfRepository, UserDefaults) throws -> Void) throws {
        let suite = "ShelfCompostTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = ShelfRepository(defaults: defaults)
        try repository.save(document)
        let shelf = ShelfController(repository: repository, now: { now }, bookmark: { _ in Data([4]) })
        defer { shelf.stop() }
        shelf.start()
        try body(shelf, repository, defaults)
    }

    @Test("Off keeps old references; enabled rules archive at the exact elapsed boundary",
          arguments: ShelfCompostPolicy.allCases)
    func ageBoundary(policy: ShelfCompostPolicy) {
        let interval = policy.interval ?? 86_400
        let old = item(age: interval + 1)
        let boundary = item(age: interval)
        let young = item(age: interval - 1)
        let future = item(age: -1)
        var document = ShelfDocument(items: [young, old, future, boundary], compostPolicy: policy)
        document.compostAgedItems(at: now)
        if policy == .off {
            #expect(document.items.count == 4)
            #expect(document.compost.isEmpty)
            #expect(document.nextCompostDate == nil)
        } else {
            #expect(document.items.map(\.id) == [young.id, future.id])
            #expect(document.compost.map(\.item) == [old, boundary])
            #expect(document.nextCompostDate == now.addingTimeInterval(1))
            let once = document
            document.compostAgedItems(at: now)
            #expect(document == once)
        }
    }

    @Test("Legacy data migrates with aging off; current data requires its archive")
    func migration() throws {
        let original = item(age: 90 * 86_400)
        let encoded = try JSONEncoder().encode(ShelfDocument(items: [original]))
        var json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json["version"] = 1
        json.removeValue(forKey: "compost")
        json.removeValue(forKey: "compostPolicy")
        let legacy = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(ShelfDocument.self, from: legacy)
        #expect(decoded.version == ShelfDocument.currentVersion)
        #expect(decoded.items == [original])
        #expect(decoded.compostPolicy == .off)
        #expect(decoded.compost.isEmpty)
        json["version"] = ShelfDocument.currentVersion
        let incomplete = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(ShelfDocument.self, from: incomplete) }
    }

    @Test("Aging survives restart and restoration preserves identity, bookmark, and a fresh age")
    func restoreUnavailableReference() throws {
        let original = item(age: 8 * 86_400)
        try withShelf(ShelfDocument(items: [original], compostPolicy: .week)) { shelf, repository, _ in
            #expect(shelf.items.isEmpty)
            #expect(try repository.load()?.compost.first?.item == original)
            shelf.start()
            try shelf.restoreFromCompost(original.id)
            let restored = try #require(shelf.items.first)
            #expect(restored.id == original.id)
            #expect(restored.bookmarkData == original.bookmarkData)
            #expect(restored.url == original.url)
            #expect(restored.addedAt == now)
            shelf.refreshCompost()
            #expect(shelf.items.count == 1)
            #expect(shelf.compost.isEmpty)
            #expect(try repository.load()?.items == [restored])
        }
    }

    @Test("A full archive retains every reference and leaves overflow on Shelf")
    func fullArchive() {
        let retained = (0..<ShelfCompostEntry.capacity - 1).map { _ in
            ShelfCompostEntry(item: item(), archivedAt: now)
        }
        let oldest = item(age: 30 * 86_400)
        let newer = item(age: 20 * 86_400)
        var document = ShelfDocument(items: [newer, oldest], compost: retained, compostPolicy: .week)
        document.compostAgedItems(at: now)
        #expect(document.compost.count == ShelfCompostEntry.capacity)
        #expect(document.compost.contains { $0.id == oldest.id })
        #expect(document.items == [newer])
        #expect(Set(document.compost.map(\.id)).isSuperset(of: retained.map(\.id)))
        #expect(document.nextCompostDate == nil)
        let full = document
        document.compostAgedItems(at: now.addingTimeInterval(365 * 86_400))
        #expect(document == full)
    }

    @Test("Choosing a rule archives existing eligible references immediately")
    func optIn() throws {
        let old = item(age: 20 * 86_400)
        try withShelf(ShelfDocument(items: [old])) { shelf, repository, _ in
            #expect(shelf.items == [old])
            try shelf.setCompostPolicy(.fortnight)
            #expect(shelf.items.isEmpty)
            #expect(try repository.load()?.compost.first?.item == old)
        }
    }

    @Test("A full Shelf refuses restoration without changing stored bytes")
    func fullShelf() throws {
        let archived = ShelfCompostEntry(item: item(), archivedAt: now)
        let document = ShelfDocument(items: (0..<ShelfDocument.capacity).map { _ in item() }, compost: [archived])
        try withShelf(document) { shelf, _, defaults in
            let before = defaults.data(forKey: "dock.shelf.v1")
            #expect(throws: ShelfCompostError.self) { try shelf.restoreFromCompost(archived.id) }
            #expect(shelf.compost == [archived])
            #expect(defaults.data(forKey: "dock.shelf.v1") == before)
        }
    }

    @Test("Clear Shelf and disabling the rule preserve Compost; forgetting is separate")
    func explicitRemoval() throws {
        let archived = ShelfCompostEntry(item: item(), archivedAt: now)
        try withShelf(ShelfDocument(items: [item()], compost: [archived], compostPolicy: .week)) {
            shelf, repository, _ in
            try shelf.clear()
            try shelf.setCompostPolicy(.off)
            #expect(try repository.load()?.compost == [archived])
            try shelf.forgetCompost(archived.id)
            #expect(try repository.load()?.compost.isEmpty == true)
        }
    }

    @Test("Re-adding a file restores its archived identity and never changes the file")
    func readdRestores() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bytes = Data("Keep this file".utf8)
        try bytes.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let original = ShelfItem(url: file, name: "File", bookmarkData: Data([1]), addedAt: now)
        try withShelf(ShelfDocument(compost: [ShelfCompostEntry(item: original, archivedAt: now)])) {
            shelf, repository, _ in
            #expect(try shelf.add([file, file]) == 0)
            #expect(shelf.items.map(\.id) == [original.id])
            #expect(try repository.load()?.compost.isEmpty == true)
            try shelf.setCompostPolicy(.week)
            try shelf.clear()
            #expect(try Data(contentsOf: file) == bytes)
        }
        try withShelf(ShelfDocument(compost: [ShelfCompostEntry(item: original, archivedAt: now)])) {
            shelf, _, _ in
            try shelf.forgetCompost(original.id)
            #expect(shelf.compost.isEmpty)
            #expect(try Data(contentsOf: file) == bytes)
        }
    }

    @Test("An identity cannot exist in both the Shelf and Compost")
    func duplicateIdentity() {
        let original = item()
        let invalid = ShelfDocument(items: [original], compost: [ShelfCompostEntry(item: original, archivedAt: now)])
        #expect(!invalid.isValid)
    }

    @Test("Unreadable Compost cannot be overwritten by choosing a rule")
    func corruptArchive() throws {
        try withShelf(ShelfDocument()) { shelf, _, defaults in
            let corrupt = Data(#"{"version":2,"items":[],"compost":"broken","compostPolicy":7}"#.utf8)
            defaults.set(corrupt, forKey: "dock.shelf.v1")
            shelf.start()
            #expect(shelf.requiresReset)
            #expect(throws: (any Error).self) { try shelf.setCompostPolicy(.week) }
            shelf.refreshCompost()
            #expect(defaults.data(forKey: "dock.shelf.v1") == corrupt)
        }
    }
}
