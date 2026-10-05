import AppKit
import Testing
@testable import DeeDock

@MainActor
struct ClipboardExhibitFileIconTests {
    @Test("A type placeholder is shared per extension and does not need the file")
    func placeholderIsShared() {
        let pdf = URL(fileURLWithPath: "/DeeDockTests/\(UUID().uuidString).pdf")
        let otherPDF = URL(fileURLWithPath: "/DeeDockTests/\(UUID().uuidString).pdf")
        let text = URL(fileURLWithPath: "/DeeDockTests/\(UUID().uuidString).txt")
        let icon = ClipboardExhibitFileIcons.placeholder(for: pdf)
        #expect(ClipboardExhibitFileIcons.placeholder(for: otherPDF) === icon)
        #expect(ClipboardExhibitFileIcons.placeholder(for: text) !== icon)
        #expect(icon.size == NSSize(width: 128, height: 128))
    }

    @Test("A resolved path is published again without another lookup")
    func cacheSkipsLookup() async {
        let path = "/DeeDockTests/\(UUID().uuidString).txt"
        let url = URL(fileURLWithPath: path)
        let image = NSImage(size: NSSize(width: 4, height: 4))
        var lookups = 0
        await ClipboardExhibitFileIcons.fill([url], load: { paths in
            lookups += 1
            return paths.map { ClipboardExhibitFileIconProbe.Loaded(path: $0, exists: true, image: image) }
        }, publish: { _, _ in })
        #expect(lookups == 1)

        lookups = 0
        var published = false
        await ClipboardExhibitFileIcons.fill([url], load: { _ in
            lookups += 1
            return []
        }, publish: { publishedPath, icon in
            published = publishedPath == path && icon.exists && icon.image === image
        })
        #expect(lookups == 0)
        #expect(published)
    }

    @Test("A cancelled fill does not publish the in-flight batch or start the next one")
    func cancelledFillDoesNotPublish() async {
        let count = ClipboardExhibitFileIcons.batchSize + 1
        let paths = (0..<count).map { "/DeeDockTests/\(UUID().uuidString)-\($0).txt" }
        let urls = paths.map { URL(fileURLWithPath: $0) }
        let gate = FileIconFillGate()
        let task = Task { @MainActor in
            var lookups = 0
            var published: [String] = []
            await ClipboardExhibitFileIcons.fill(urls, load: { batch in
                lookups += 1
                await gate.block()
                return batch.map {
                    ClipboardExhibitFileIconProbe.Loaded(path: $0, exists: true, image: NSImage(size: .zero))
                }
            }, publish: { path, _ in
                published.append(path)
            })
            return (lookups, published)
        }
        await gate.untilEntered()
        task.cancel()
        gate.unblock()
        let (lookups, published) = await task.value
        #expect(lookups == 1)
        #expect(published.isEmpty)
        #expect(paths.allSatisfy { ClipboardExhibitFileIcons.cached($0) == nil })
    }
}

/// Blocks inside an injected icon load so a test can cancel the fill mid-batch.
@MainActor private final class FileIconFillGate {
    private var blocked = true
    private var entered = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var blockers: [CheckedContinuation<Void, Never>] = []

    func block() async {
        entered = true
        let waiters = enteredWaiters
        enteredWaiters.removeAll()
        waiters.forEach { $0.resume() }
        guard blocked else { return }
        await withCheckedContinuation { blockers.append($0) }
    }

    func untilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func unblock() {
        blocked = false
        blockers.forEach { $0.resume() }
        blockers.removeAll()
    }
}
