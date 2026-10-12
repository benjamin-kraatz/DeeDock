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
nonisolated enum LookoutPictureReading {
    /// The largest picture file read: the indexer's limit (`QueuedFileGate.maxReadBytes`).
    static let maxBytes = 512 << 20

    /// A picture file. Sized as a screenshot when macOS or its name says it is one, as the indexer does.
    ///
    /// The read and the decode run on a worker of their own, which cancelling the caller cancels: a search that's
    /// replaced stops reading between 8 MB pieces and doesn't decode, so replacing big pictures one after another
    /// never holds several of their buffers.
    ///
    /// - Throws: `QueryPicture.Failure`, the read's error, or `CancellationError`.
    static func picture(at url: URL) async throws -> QueryPicture {
        try await cancellably {
            let data = try bytes(at: url, checkCancellation: Task.checkCancellation)
            try Task.checkCancellation()
            let source = try source(data, typeHint: UTType(filenameExtension: url.pathExtension))
            return try QueryPicture.make(from: source, screenshot: Rules.isScreenshot(url))
        }
    }

    /// Runs `work` on a detached worker at user-initiated priority, and cancels the worker when the calling task is
    /// cancelled (a detached task doesn't inherit cancellation). A caller that's cancelled already starts nothing.
    private static func cancellably<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated, operation: work)
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
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

    /// Pasted picture bytes. Sized as a screenshot: what people paste is mostly what they just captured. Decoded on a
    /// worker that cancelling the caller cancels.
    ///
    /// - Throws: `QueryPicture.Failure`, or `CancellationError`.
    static func picture(from data: Data) async throws -> QueryPicture {
        try await cancellably {
            try Task.checkCancellation()
            return try QueryPicture.make(from: source(data, typeHint: nil), screenshot: true)
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
