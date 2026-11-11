import Foundation
@testable import DeeDock

/// A fresh temporary directory that is removed when the value is released. Every Vapor test that
/// touches the file system works only inside one of these.
final class VaporTempDirectory {
    let url: URL

    init(_ label: String = "vapor") throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    /// Creates a folder (and its parents) at `path` inside the directory.
    @discardableResult
    func folder(_ path: String) throws -> URL {
        let folder = url.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Creates a file with `bytes` bytes at `path`, creating parents.
    @discardableResult
    func file(_ path: String, bytes: Int = 16) throws -> URL {
        let file = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: file)
        return file
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
}

/// A sleep the test fires by hand. Each call suspends until `fire(_:)` is called with its
/// duration, or the sleeping task is cancelled (which throws, like `Task.sleep`).
final class VaporManualSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [UUID: (Duration, CheckedContinuation<Void, any Error>)] = [:]

    var sleep: @Sendable (Duration) async throws -> Void {
        { [self] duration in
            let id = UUID()
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    lock.withLock { waiters[id] = (duration, continuation) }
                    // Cancelled before registering: the handler below already ran and found nothing.
                    if Task.isCancelled, let waiter = lock.withLock({ waiters.removeValue(forKey: id) }) {
                        waiter.1.resume(throwing: CancellationError())
                    }
                }
            } onCancel: {
                let waiter = lock.withLock { waiters.removeValue(forKey: id) }
                waiter?.1.resume(throwing: CancellationError())
            }
        }
    }

    /// Durations still sleeping.
    var pending: [Duration] { lock.withLock { waiters.values.map(\.0) } }

    /// Wakes every sleep of exactly `duration`.
    func fire(_ duration: Duration) {
        let ready = lock.withLock { () -> [CheckedContinuation<Void, any Error>] in
            let matches = waiters.filter { $0.value.0 == duration }
            matches.keys.forEach { waiters.removeValue(forKey: $0) }
            return matches.values.map(\.1)
        }
        ready.forEach { $0.resume() }
    }
}

/// Yields until `condition` holds, so tasks resumed on the main actor get to run.
@MainActor
func vaporSettle(_ condition: () -> Bool) async {
    for _ in 0..<400 where !condition() {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(1))
    }
}

/// Returns a fixed measurement right away, so rows don't stay pending in controller tests.
struct VaporFixedMeasurer: VaporMeasuring {
    var result: VaporMeasurement = .measured(bytes: 1_000, files: 3)
    func measure(_ url: URL) async -> VaporMeasurement { result }
}

/// Never finishes measuring until cancelled, for pending-state tests.
struct VaporStalledMeasurer: VaporMeasuring {
    func measure(_ url: URL) async -> VaporMeasurement {
        while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
        return .pending
    }
}
