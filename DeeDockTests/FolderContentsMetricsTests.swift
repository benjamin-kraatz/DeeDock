import Foundation
import Testing

struct FolderContentsMetricsTests {
    @Test("An empty folder reports zero items and zero bytes")
    func emptyFolder() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let metrics = try FolderContentsEnumerator.measure(url: root)
        #expect(metrics.immediateItemCount == 0)
        #expect(metrics.recursiveItemCount == 0)
        #expect(metrics.totalByteCount == 0)
        #expect(metrics.completeness == .complete)
    }

    @Test("Immediate count excludes nested items while size includes them")
    func nestedTotals() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 1, count: 100).write(to: root.appendingPathComponent("a.txt"))
        try Data(repeating: 2, count: 40).write(to: root.appendingPathComponent("b.txt"))
        let nested = root.appendingPathComponent("Nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        try Data(repeating: 3, count: 25).write(to: nested.appendingPathComponent("c.txt"))
        try Data().write(to: root.appendingPathComponent(".hidden"))

        let metrics = try FolderContentsEnumerator.measure(url: root)
        #expect(metrics.immediateItemCount == 3)
        #expect(metrics.recursiveItemCount == 4)
        #expect(metrics.totalByteCount == 165)
        #expect(metrics.completeness == .complete)
    }

    @Test("Packages count as one item and contribute contained file bytes")
    func packageContents() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("Document.rtfd")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
        try Data(repeating: 9, count: 80).write(to: package.appendingPathComponent("TXT.rtf"))
        try Data(repeating: 4, count: 20).write(to: root.appendingPathComponent("aside.txt"))

        let metrics = try FolderContentsEnumerator.measure(url: root)
        #expect(metrics.immediateItemCount == 2)
        #expect(metrics.recursiveItemCount == 2)
        #expect(metrics.totalByteCount == 100)
        #expect(metrics.completeness == .complete)
    }

    @Test("Symbolic links are leaves and do not add the target's contents")
    func symbolicLinkIsLeaf() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("Outside")
        let measured = root.appendingPathComponent("Measured")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: measured, withIntermediateDirectories: false)
        try Data(repeating: 5, count: 500).write(to: outside.appendingPathComponent("big.txt"))
        try Data(repeating: 6, count: 10).write(to: measured.appendingPathComponent("small.txt"))
        try FileManager.default.createSymbolicLink(
            at: measured.appendingPathComponent("Loop"),
            withDestinationURL: measured
        )
        try FileManager.default.createSymbolicLink(
            at: measured.appendingPathComponent("Away"),
            withDestinationURL: outside
        )

        let metrics = try FolderContentsEnumerator.measure(url: measured)
        let bytes = try #require(metrics.totalByteCount)
        #expect(metrics.immediateItemCount == 3)
        #expect(metrics.recursiveItemCount == 3)
        #expect(bytes >= 10 && bytes < 500)
        #expect(metrics.completeness == .complete)
    }

    @Test("An unreadable descendant finishes as an incomplete total")
    func inaccessibleDescendant() throws {
        let root = try temporaryDirectory()
        defer {
            let locked = root.appendingPathComponent("Locked")
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: root)
        }
        try Data(repeating: 7, count: 15).write(to: root.appendingPathComponent("visible.txt"))
        let locked = root.appendingPathComponent("Locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: false)
        try Data(repeating: 8, count: 30).write(to: locked.appendingPathComponent("secret.txt"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)

        let metrics = try FolderContentsEnumerator.measure(url: root)
        #expect(metrics.immediateItemCount == 2)
        #expect(metrics.completeness == .incomplete)
        #expect(metrics.totalByteCount == 15)
    }

    @Test("Size sort uses finished folder totals and keeps calculating folders last")
    func sizeSortOrder() {
        let smallFile = FolderStackEntryReference(
            url: URL(fileURLWithPath: "/Preview/small.txt"), name: "small.txt",
            isFolder: false, byteCount: 10
        )
        let largeFile = FolderStackEntryReference(
            url: URL(fileURLWithPath: "/Preview/large.txt"), name: "large.txt",
            isFolder: false, byteCount: 500
        )
        let pendingFolder = FolderStackEntryReference(
            url: URL(fileURLWithPath: "/Preview/Pending"), name: "Pending",
            isFolder: true, byteCount: 96,
            contents: .calculating(immediateItemCount: 20)
        )
        let largeFolder = FolderStackEntryReference(
            url: URL(fileURLWithPath: "/Preview/Photos"), name: "Photos",
            isFolder: true, byteCount: 64,
            contents: FolderContentsMetrics(immediateItemCount: 2, recursiveItemCount: 2,
                                           totalByteCount: 400, completeness: .complete)
        )
        let items = [smallFile, largeFile, pendingFolder, largeFolder]
        let sorted = items.sorted { FolderStackSort.size.precedes($0, $1) }
        #expect(sorted.map(\.name) == ["large.txt", "Photos", "small.txt", "Pending"])
        #expect(pendingFolder.sizeSortByteCount == -1)
        #expect(largeFolder.sizeSortByteCount == 400)
        #expect(largeFolder.byteCount == 64)
    }

    @Test("Folder details never treat directory-entry size as a contents total")
    func detailsRejectDirectoryEntrySize() {
        let metadataOnly = FolderStackEntryReference(
            url: URL(fileURLWithPath: "/Preview/Bare"), name: "Bare",
            isFolder: true, byteCount: 96
        )
        #expect(FolderStackItemDetails(reference: metadataOnly).size == nil)
        #expect(FolderStackItemDetails(reference: metadataOnly).itemCountText == nil)

        let complete = metadataOnly.withContents(
            FolderContentsMetrics(immediateItemCount: 2, recursiveItemCount: 5,
                                  totalByteCount: 1_500_000, completeness: .complete)
        )
        let details = FolderStackItemDetails(reference: complete)
        #expect(details.size == ByteCountFormatter.string(fromByteCount: 1_500_000, countStyle: .file))
        #expect(details.size != ByteCountFormatter.string(fromByteCount: 96, countStyle: .file))
        #expect(details.summary.contains(details.size ?? ""))
        #expect(details.help.contains(String(localized: .folderDetailsTotalSize)))
        #expect(details.help.contains(String(localized: .folderDetailsNestedItemCount(5))))

        let calculating = metadataOnly.withContents(.calculating(immediateItemCount: 8))
        #expect(FolderStackItemDetails(reference: calculating).size == String(localized: .folderDetailsCalculating))

        let incomplete = metadataOnly.withContents(
            FolderContentsMetrics(immediateItemCount: 1, recursiveItemCount: 1,
                                  totalByteCount: 220_000, completeness: .incomplete)
        )
        let formatted = ByteCountFormatter.string(fromByteCount: 220_000, countStyle: .file)
        #expect(FolderStackItemDetails(reference: incomplete).size == String(localized: .folderDetailsIncompleteSize(formatted)))
    }

    @Test("Cache hits require the same modification date")
    func cacheUsesModificationDate() async {
        let url = URL(fileURLWithPath: "/Preview/Cached-\(UUID().uuidString)")
        let first = Date(timeIntervalSince1970: 100)
        let metrics = FolderContentsMetrics(immediateItemCount: 1, recursiveItemCount: 1,
                                            totalByteCount: 50, completeness: .complete)
        await FolderContentsMetricsCache.shared.store(metrics, for: url, modifiedAt: first)
        #expect(await FolderContentsMetricsCache.shared.finalMetrics(for: url, modifiedAt: first) == metrics)
        #expect(await FolderContentsMetricsCache.shared.finalMetrics(for: url, modifiedAt: first.addingTimeInterval(1)) == nil)
        await FolderContentsMetricsCache.shared.remove(at: url)
        #expect(await FolderContentsMetricsCache.shared.finalMetrics(for: url, modifiedAt: first) == nil)
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Dee31-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
