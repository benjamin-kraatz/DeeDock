import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What a search with a picture starts from.
nonisolated enum LookoutPictureInput: Sendable, Equatable {
    /// A picture file to read: a drop, a copied picture file, or Find Similar on a picture outside the index.
    case file(URL)
    /// Picture bytes from the pasteboard (PNG, TIFF, JPEG…).
    case data(Data)
    /// A file in the index: Find Similar reuses its stored vector (`segmentID` preferred, the segment a Lookout hit
    /// matched). When the index has no vector for it and it's a picture, `fallback` is read instead.
    case indexed(path: String, segmentID: Int64?, fallback: URL?)

    /// The file searched with, which its results leave out. Nil for pasted bytes.
    var excludedPath: String? {
        switch self {
        case .file(let url): url.path
        case .data: nil
        case .indexed(let path, _, _): path
        }
    }
}

/// Reads a picture to search with into memory, sized for the encoder (`QueryPicture`), off the main actor. Nothing is
/// written anywhere: the bytes are read once and dropped when the search has its vector.
///
/// The read (blocking `pread`s of up to 512 MB) and the decode and resize (CPU-bound: about 0.15 s in Release, nearly
/// a second in Debug) run on `queue`, a dispatch queue of their own, never on Swift's cooperative thread pool. That
/// pool has one thread per core; work that blocks one starves every task and actor waiting for a thread, which is
/// how parallel tests on a few cores timed out, and how a slow volume would stall the app's other async work.
nonisolated enum LookoutPictureReading {
    /// The largest picture file read: the indexer's limit (`QueuedFileGate.maxReadBytes`).
    static let maxBytes = 512 << 20

    /// A picture file. Sized as a screenshot when macOS or its name says it is one, as the indexer does.
    ///
    /// The read and the decode run on `queue`, and cancelling the caller reaches them: a search that's replaced stops
    /// reading between 8 MB pieces and doesn't decode, so replacing big pictures one after another never holds
    /// several of their buffers.
    ///
    /// - Throws: `QueryPicture.Failure`, the read's error, or `CancellationError`.
    static func picture(at url: URL) async throws -> QueryPicture {
        try await onQueue { cancellation in
            let data = try bytes(at: url, checkCancellation: cancellation.check)
            try cancellation.check()
            let source = try source(data, typeHint: UTType(filenameExtension: url.pathExtension))
            return try QueryPicture.make(from: source, screenshot: Rules.isScreenshot(url))
        }
    }

    /// Where pictures are read and decoded: concurrent, so a replaced search finishing its last piece never holds up
    /// the next one, at user-initiated QoS, as a search the person is waiting for.
    private static let queue = DispatchQueue(label: "Lookout.PictureReading", qos: .userInitiated,
                                             attributes: .concurrent)

    /// Cancellation for work on `queue`, where `Task.checkCancellation` can't see the caller's task: the caller's
    /// cancellation handler sets it, and the work checks it between steps.
    final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false   // guarded by `lock`

        func cancel() { lock.withLock { cancelled = true } }

        /// - Throws: `CancellationError` once `cancel()` was called.
        func check() throws {
            if lock.withLock({ cancelled }) { throw CancellationError() }
        }
    }

    /// Runs `work` on `queue` and hands back its result. Cancelling the calling task cancels `work` through the
    /// `Cancellation` it's given; a caller that's cancelled already starts nothing.
    private static func onQueue<T: Sendable>(_ work: @escaping @Sendable (Cancellation) throws -> T) async throws -> T {
        try Task.checkCancellation()
        let cancellation = Cancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    continuation.resume(with: Result { try cancellation.check(); return try work(cancellation) })
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    /// The bytes of the file at `url`, read from one descriptor: it's opened once, `fstat` on that descriptor must
    /// say it's a regular file within `maxBytes`, and the read takes at most that size from the same descriptor in
    /// `pread`s (`QueuedFileGate.contents(of:size:)`), never memory-mapped. Checking the path and then opening it
    /// again would let a file swapped in between get past the size cap. Anything that can't be checked fails.
    ///
    /// - Throws: `QueryPicture.Failure.unreadable` when the file can't be opened or checked, isn't a regular file, or
    ///   is too large; the read's error otherwise.
    /// - Parameter checkCancellation: Asked before the buffer is allocated and between pieces of the read.
    static func bytes(at url: URL, maxBytes: Int = LookoutPictureReading.maxBytes,
                      checkCancellation: () throws -> Void = {}) throws -> Data {
        // O_NONBLOCK: a FIFO dropped in its place must not block the open; it's refused below.
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw QueryPicture.Failure.unreadable }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_size >= 0,
              info.st_size <= maxBytes else { throw QueryPicture.Failure.unreadable }
        return try QueuedFileGate.contents(of: descriptor, size: Int(info.st_size),
                                           checkCancellation: checkCancellation)
    }

    /// Pasted picture bytes. Sized as a screenshot: what people paste is mostly what they just captured. Decoded on
    /// `queue`; a caller cancelled before it starts decodes nothing.
    ///
    /// - Throws: `QueryPicture.Failure`, or `CancellationError`.
    static func picture(from data: Data) async throws -> QueryPicture {
        try await onQueue { _ in
            try QueryPicture.make(from: source(data, typeHint: nil), screenshot: true)
        }
    }

    private static func source(_ data: Data, typeHint: UTType?) throws -> CGImageSource {
        var options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        if let typeHint { options[kCGImageSourceTypeIdentifierHint] = typeHint.identifier }
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            throw QueryPicture.Failure.unreadable
        }
        return source
    }
}
