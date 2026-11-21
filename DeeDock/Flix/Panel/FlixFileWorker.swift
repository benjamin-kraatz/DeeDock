import Foundation

/// Runs Flix Files' file commands off the main actor, one at a time, in the order they were asked.
///
/// A move across volumes copies the whole file, and a folder on a network share can take seconds;
/// on the main actor that would freeze the dock. Each command (move, rename, Trash's identity check,
/// Tidy, Undo) is one block on a private serial dispatch queue rather than a Swift concurrency task,
/// because a long copy blocks its thread and must not hold one of the cooperative pool's few. FIFO
/// order keeps an Undo behind the move it undoes. A block that started always finishes: a half-done
/// move cannot be cancelled safely, so closing the panel does not stop it, and its result is applied
/// to the history when it arrives (by item identifier, so later changes are not overwritten).
nonisolated final class FlixFileWorker: Sendable {
    static let shared = FlixFileWorker()

    private let queue = DispatchQueue(label: "dokk.flix.files", qos: .userInitiated)

    init() {}

    /// Runs `work` after every block enqueued before it and returns its result to the caller's actor.
    func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }
}
