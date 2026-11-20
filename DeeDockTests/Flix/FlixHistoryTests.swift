import Foundation
import Testing
@testable import DeeDock

/// The history's merge rules: one item per path, newest first, removals that stick, a cap that
/// spares flagged items, and persistence that survives a round trip.
struct FlixHistoryTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(_ path: String, _ activity: FlixActivity = .opened, at offset: TimeInterval,
                       kind: FlixItemKind = .document) -> FlixActivityEvent {
        FlixActivityEvent(path: path, name: (path as NSString).lastPathComponent, kind: kind, activity: activity,
                          date: t0.addingTimeInterval(offset))
    }

    @Test func newerEventsMoveAnItemUpAndKeepItsIdentity() {
        var document = FlixHistoryDocument()
        document.record(event("/a/report.pdf", .downloaded, at: 0))
        document.record(event("/a/notes.txt", at: 10))
        let id = document.items.last!.id
        document.items[1].isFlagged = true
        document.record(event("/a/report.pdf", .opened, at: 20))
        #expect(document.items.map(\.path) == ["/a/report.pdf", "/a/notes.txt"])
        #expect(document.items[0].id == id)
        #expect(document.items[0].activity == .opened)
        #expect(document.items[0].isFlagged)
        #expect(document.items[0].firstSeen == t0)
    }

    @Test func olderEventsOnlyFillInDetails() {
        var document = FlixHistoryDocument()
        document.record(event("/a/report.pdf", .opened, at: 50))
        var older = event("/a/report.pdf", .downloaded, at: 10)
        older.sourcePage = URL(string: "https://example.com/files")
        document.record(older)
        #expect(document.items.count == 1)
        #expect(document.items[0].activity == .opened)
        #expect(document.items[0].date == t0.addingTimeInterval(50))
        #expect(document.items[0].sourcePage?.host() == "example.com")
    }

    @Test func aDownloadWinsATieWithNew() {
        var document = FlixHistoryDocument()
        document.record(event("/d/file.zip", .created, at: 5))
        document.record(event("/d/file.zip", .downloaded, at: 5))
        #expect(document.items[0].activity == .downloaded)
    }

    @Test func pathsAreStandardizedSoDuplicatesMerge() {
        var document = FlixHistoryDocument()
        document.record(event("/a/b/../report.pdf", at: 0))
        document.record(event("/a/report.pdf", at: 1))
        #expect(document.items.count == 1)
        #expect(document.items[0].path == "/a/report.pdf")
    }

    @Test func removedItemsReturnOnlyWithNewerActivity() {
        var document = FlixHistoryDocument()
        document.record(event("/a/report.pdf", at: 0))
        document.remove(Set(document.items.map(\.id)), at: t0.addingTimeInterval(100))
        #expect(document.items.isEmpty)
        let stale = document.record(event("/a/report.pdf", at: 50))
        #expect(!stale)
        #expect(document.items.isEmpty)
        let fresh = document.record(event("/a/report.pdf", at: 150))
        #expect(fresh)
        #expect(document.items.count == 1)
        #expect(document.removed.isEmpty)
    }

    @Test func undoRestoresRemovedItems() {
        var document = FlixHistoryDocument()
        document.record(event("/a/one.pdf", at: 0))
        document.record(event("/a/two.pdf", at: 10))
        let removed = document.items.filter { $0.path == "/a/one.pdf" }
        document.remove(Set(removed.map(\.id)))
        document.restore(removed)
        #expect(document.items.map(\.path) == ["/a/two.pdf", "/a/one.pdf"])
        #expect(document.removed.isEmpty)
    }

    @Test func theCapDropsTheOldestButNeverFlaggedItems() {
        var document = FlixHistoryDocument()
        document.record(event("/old/flagged.pdf", at: -1))
        document.setFlagged(true, for: Set(document.items.map(\.id)))
        for index in 0..<(FlixHistoryDocument.capacity + 5) {
            document.record(event("/many/\(index).pdf", at: TimeInterval(index)))
        }
        #expect(document.items.count == FlixHistoryDocument.capacity + 1)
        #expect(document.items.contains { $0.path == "/old/flagged.pdf" })
        #expect(!document.items.contains { $0.path == "/many/0.pdf" })
        #expect(document.items.first?.path == "/many/\(FlixHistoryDocument.capacity + 4).pdf")
    }

    @Test func noiseHasItsOwnSmallerCap() {
        var document = FlixHistoryDocument()
        for index in 0..<(FlixHistoryDocument.noiseCapacity + 10) {
            document.record(event("/p/DerivedData/x/\(index).o", .saved, at: TimeInterval(index)))
        }
        document.record(event("/a/real.pdf", at: -10))
        #expect(document.items.count == FlixHistoryDocument.noiseCapacity + 1)
        #expect(document.items.contains { $0.path == "/a/real.pdf" })
    }

    @Test func aFinishedDownloadReplacesItsPartialEntry() {
        var document = FlixHistoryDocument()
        document.record(event("/Downloads/Report.pdf.crdownload", .created, at: 0))
        document.record(event("/Downloads/Report.pdf", .downloaded, at: 5))
        #expect(document.items.map(\.path) == ["/Downloads/Report.pdf"])
    }

    @Test func unseenCountsArrivalsSinceTheLastLook() {
        var document = FlixHistoryDocument()
        document.record(event("/d/a.pdf", .downloaded, at: 0))
        document.record(event("/d/b.png", .created, at: 10))
        document.record(event("/d/c.pdf", .opened, at: 20))
        document.record(event("/d/c.pdf.part", .created, at: 25))
        #expect(document.unseenCount() == 2)
        #expect(document.unseenCount(hidingNoise: false) == 3)
        document.lastSeen = t0.addingTimeInterval(5)
        #expect(document.unseenCount() == 1)
    }

    @Test func relocateKeepsIdentityAndDropsAnyItemAlreadyThere() {
        var document = FlixHistoryDocument()
        document.record(event("/d/a.pdf", at: 0))
        document.record(event("/e/a.pdf", at: 1))
        let moving = document.items.first { $0.path == "/d/a.pdf" }!.id
        document.relocate(moving, to: "/e/a.pdf", name: "a.pdf")
        #expect(document.items.count == 1)
        #expect(document.items[0].id == moving)
        #expect(document.items[0].path == "/e/a.pdf")
    }

    @Test func decodingNormalizesOrderAndDuplicates() throws {
        var document = FlixHistoryDocument()
        let older = FlixItem(path: "/a/x.pdf", name: "x.pdf", kind: .document, activity: .opened, date: t0)
        let newer = FlixItem(path: "/a/y.pdf", name: "y.pdf", kind: .document, activity: .opened, date: t0.addingTimeInterval(9))
        let duplicate = FlixItem(path: "/a/x.pdf", name: "x.pdf", kind: .document, activity: .saved, date: t0.addingTimeInterval(-9))
        document.items = [older, newer, duplicate]
        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(FlixHistoryDocument.self, from: data)
        #expect(decoded.items.map(\.path) == ["/a/y.pdf", "/a/x.pdf"])
        #expect(decoded.items[1].activity == .opened)
    }

    @Test func aDocumentWithoutKeysDecodesEmpty() throws {
        let decoded = try JSONDecoder().decode(FlixHistoryDocument.self, from: Data("{}".utf8))
        #expect(decoded.items.isEmpty && decoded.removed.isEmpty && decoded.lastSeen == .distantPast)
        let library = try JSONDecoder().decode(FlixLibraryDocument.self, from: Data("{}".utf8))
        #expect(library.favorites.isEmpty && library.smartFilters.isEmpty)
    }

    @MainActor @Test func theHistoryPersistsAndSurvivesAnUnreadableFile() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "flix-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let history = FlixHistory(folder: folder)
        history.record(event("/a/report.pdf", .downloaded, at: 0))
        history.addFavorite(FlixFavorite(kind: .folder, path: "/a", name: "a"))
        history.saveSmartFilter(FlixSmartFilter(name: "PDFs", rules: [.fileExtension("pdf")]))
        history.flush()

        let reloaded = FlixHistory(folder: folder)
        reloaded.load()
        #expect(reloaded.items.map(\.path) == ["/a/report.pdf"])
        #expect(reloaded.favorites.map(\.path) == ["/a"])
        #expect(reloaded.smartFilters.map(\.name) == ["PDFs"])
        #expect(!reloaded.recoveredFromUnreadableFile)

        try Data("{ broken".utf8).write(to: folder.appending(path: "history.json"))
        let recovered = FlixHistory(folder: folder)
        recovered.load()
        #expect(recovered.recoveredFromUnreadableFile)
        #expect(recovered.items.isEmpty)
        #expect(recovered.favorites.count == 1)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names.contains { $0.hasPrefix("history.unreadable-") })
    }

    @Test func storageFoldersAreSeparatePerAppIdentity() {
        #expect(FlixStorageLocation.folderName(bundleIdentifier: "de.benjaminkraatz.DeeDock") == "Flix")
        #expect(FlixStorageLocation.folderName(bundleIdentifier: "de.benjaminkraatz.DeeDock.dev") == "Flix-dev")
        #expect(FlixStorageLocation.folderName(bundleIdentifier: "com.example/other") == "Flix-com-example-other")
        let base = URL(fileURLWithPath: "/tmp/support")
        #expect(FlixStorageLocation.folder(bundleIdentifier: "de.benjaminkraatz.DeeDock.dev", applicationSupport: base).path
                == "/tmp/support/DDock/Flix-dev")
    }

    @Test func downloadSourcesKeepNoTokens() {
        let page = FlixPaths.sourcePage(fromWhereFroms: ["https://cdn.example.com/f.pdf?sig=abc",
                                                         "https://billing.example.com/invoices?token=secret#top"])
        #expect(page?.absoluteString == "https://billing.example.com/invoices")
        #expect(FlixPaths.sourcePage(fromWhereFroms: ["https://u:p@cdn.example.com/f.pdf?x=1"])?.absoluteString
                == "https://cdn.example.com/f.pdf")
        #expect(FlixPaths.sourcePage(fromWhereFroms: ["file:///tmp/x"]) == nil)
    }
}
