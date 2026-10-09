import Foundation
import Testing
@testable import DeeDock

@MainActor
struct HubFileTransferQueueTests {
    /// A fresh temporary folder per test, removed when the test ends.
    private final class Sandbox {
        let root: URL
        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("HubFileTransferQueueTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        deinit { try? FileManager.default.removeItem(at: root) }

        func folder(_ path: String) throws -> URL {
            let url = root.appendingPathComponent(path, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        func file(_ path: String, bytes: Int = 64) throws -> URL {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 7, count: bytes).write(to: url)
            return url
        }

        func exists(_ path: String) -> Bool {
            FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)
        }
    }

    private let copy = String(localized: .hubFilesCopySuffix)

    // MARK: Rules

    @Test func optionForcesCopyAndSameVolumeMoves() throws {
        let box = try Sandbox()
        let source = try box.file("a/one.txt")
        let target = try box.folder("b")
        #expect(HubFileTransferQueue.defaultKind(sources: [source], destination: target, optionHeld: false) == .move)
        #expect(HubFileTransferQueue.defaultKind(sources: [source], destination: target, optionHeld: true) == .copy)
    }

    @Test func dropIntoSelfOrDescendantIsInvalid() throws {
        let box = try Sandbox()
        let folder = try box.folder("parent/child")
        let parent = folder.deletingLastPathComponent()
        let sibling = try box.folder("parent-sibling")
        #expect(!HubFileTransferQueue.isValidDrop(sources: [parent], destination: parent))
        #expect(!HubFileTransferQueue.isValidDrop(sources: [parent], destination: folder))
        // A shared name prefix is not ancestry.
        #expect(HubFileTransferQueue.isValidDrop(sources: [sibling], destination: folder))
        #expect(!HubFileTransferQueue.isValidDrop(sources: [], destination: folder))
    }

    @Test func dropIntoOwnParentIsInvalidOnlyWhenEveryItemIsThere() throws {
        let box = try Sandbox()
        let here = try box.file("here/a.txt")
        let other = try box.file("other/b.txt")
        let folder = here.deletingLastPathComponent()
        #expect(!HubFileTransferQueue.isValidDrop(sources: [here], destination: folder))
        #expect(HubFileTransferQueue.isValidDrop(sources: [here, other], destination: folder))
    }

    // MARK: Round trips

    @Test func copyLeavesSourceAndNamesCollisions() async throws {
        let box = try Sandbox()
        let source = try box.file("src/note.txt", bytes: 300)
        let folder = try box.file("src/tree/inner.txt", bytes: 200).deletingLastPathComponent()
        let target = try box.folder("dst")
        _ = try box.file("dst/note.txt")
        let queue = HubFileTransferQueue()
        queue.enqueue(.copy, sources: [source, folder], to: target)
        await queue.waitUntilIdle()

        #expect(queue.lastFinished?.state == .finished)
        #expect(queue.lastFinished?.totalBytes == 500)
        #expect(queue.jobs.isEmpty && queue.overallProgress == nil)
        #expect(box.exists("src/note.txt") && box.exists("src/tree/inner.txt"))
        #expect(box.exists("dst/note \(copy).txt"))
        #expect(box.exists("dst/tree/inner.txt"))
    }

    @Test func copyIntoSameFolderDuplicates() async throws {
        let box = try Sandbox()
        let source = try box.file("src/note.txt")
        let queue = HubFileTransferQueue()
        queue.enqueue(.copy, sources: [source], to: source.deletingLastPathComponent())
        await queue.waitUntilIdle()
        #expect(box.exists("src/note.txt") && box.exists("src/note \(copy).txt"))
    }

    @Test func sameVolumeMoveRenamesWithoutOverwriting() async throws {
        let box = try Sandbox()
        let source = try box.file("src/note.txt", bytes: 10)
        let target = try box.folder("dst")
        let existing = try box.file("dst/note.txt", bytes: 3)
        let queue = HubFileTransferQueue()
        queue.enqueue(.move, sources: [source], to: target)
        await queue.waitUntilIdle()

        #expect(queue.lastFinished?.state == .finished)
        #expect(!box.exists("src/note.txt"))
        #expect(try Data(contentsOf: existing).count == 3)
        #expect(box.exists("dst/note \(copy).txt"))
    }

    @Test func moveIntoOwnFolderDoesNothing() async throws {
        let box = try Sandbox()
        let source = try box.file("src/note.txt")
        let queue = HubFileTransferQueue()
        queue.enqueue(.move, sources: [source], to: source.deletingLastPathComponent())
        #expect(queue.jobs.isEmpty)
        #expect(box.exists("src/note.txt") && !box.exists("src/note \(copy).txt"))
    }

    @Test func cancelMidCopyRemovesPartialItemAndKeepsSource() async throws {
        let box = try Sandbox()
        for index in 0..<5 { _ = try box.file("src/tree/file\(index).txt", bytes: 4096) }
        let folder = box.root.appendingPathComponent("src/tree")
        let target = try box.folder("dst")
        // Cancels from the first copyfile status callback, before any file is complete.
        let queue = HubFileTransferQueue(callbackHook: { $0.cancel() })
        queue.enqueue(.copy, sources: [folder], to: target)
        await queue.waitUntilIdle()

        #expect(queue.lastFinished?.state == .cancelled)
        #expect(!box.exists("dst/tree"))
        #expect(box.exists("src/tree/file4.txt"))
    }

    @Test func pausedJobWaitsUntilResumed() async throws {
        let box = try Sandbox()
        let source = try box.file("src/note.txt")
        let target = try box.folder("dst")
        let blocker = try box.file("src/first.txt")
        let queue = HubFileTransferQueue()
        // The first job holds the worker while the second is paused before it starts.
        let first = queue.enqueue(.copy, sources: [blocker], to: target)
        let second = queue.enqueue(.copy, sources: [source], to: target)
        queue.pause(second)
        #expect(queue.jobs.first { $0.id == second }?.state == .paused)
        queue.resume(second)
        queue.cancel(first)
        await queue.waitUntilIdle()
        #expect(box.exists("dst/note.txt"))
    }
}
