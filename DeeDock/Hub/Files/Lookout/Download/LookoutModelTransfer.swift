import Foundation

/// Moves one model file from Hugging Face into its partial file, continuing from the bytes already there with an
/// HTTP range request. It neither verifies nor installs the file (`LookoutModelInstaller` does both).
///
/// Range requests are safe without `If-Range`: the URL names one pinned revision of the repository
/// (`ModelFiles.revision`), whose files never change. A `200` instead of a `206` means the server sent the whole
/// file, so the partial starts over; a `416` means the partial can't be continued (`rangeNotSatisfiable`), and the
/// caller deletes it and asks once more.
///
/// Threads: every delegate callback and all state live on `queue`, one serial operation queue. The session holds
/// its delegate strongly until the task ends, when `finishTasksAndInvalidate` lets both go.
nonisolated final class LookoutModelTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    /// The server can't continue the partial file; delete it and start again.
    struct RangeNotSatisfiable: Error {}

    /// Progress is reported at most this often (in bytes), so a 555 MB file sends about 550 updates.
    static let reportInterval: Int64 = 1 << 20

    private let partial: URL
    private let expectedBytes: Int64
    private let progress: @Sendable (Int64) -> Void
    private let queue: OperationQueue

    // The queue's state.
    private var handle: FileHandle?
    private var offset: Int64
    private var received: Int64
    private var lastReported: Int64 = 0
    private var failure: Error?
    private var continuation: CheckedContinuation<Void, Error>?

    private init(partial: URL, offset: Int64, expectedBytes: Int64, progress: @escaping @Sendable (Int64) -> Void) {
        self.partial = partial
        self.offset = offset
        self.received = offset
        self.expectedBytes = expectedBytes
        self.progress = progress
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "Lookout.ModelTransfer"
        super.init()
    }

    /// Fetches `url` into `partial` until it holds `expectedBytes`, resuming what's there.
    ///
    /// - Parameters:
    ///   - configuration: The session's configuration (tests pass one with a fake `URLProtocol`).
    ///   - progress: The bytes now in the partial file, from the transfer's queue.
    /// - Throws: `LookoutDownloadError`, `RangeNotSatisfiable`, or `CancellationError` when the calling task is
    ///   cancelled (the partial file stays for the next attempt).
    static func run(url: URL, partial: URL, expectedBytes: Int64, configuration: URLSessionConfiguration,
                    progress: @escaping @Sendable (Int64) -> Void) async throws {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw LookoutDownloadError.write(reason: error.localizedDescription)
        }
        var existing = (try? fileManager.attributesOfItem(atPath: partial.path)[.size] as? Int64) ?? 0
        if existing > expectedBytes {
            try? fileManager.removeItem(at: partial)
            existing = 0
        }
        progress(existing)
        if existing == expectedBytes { return }

        var request = URLRequest(url: url)
        if existing > 0 { request.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range") }
        let transfer = LookoutModelTransfer(partial: partial, offset: existing, expectedBytes: expectedBytes,
                                            progress: progress)
        let session = URLSession(configuration: configuration, delegate: transfer, delegateQueue: transfer.queue)
        let task = session.dataTask(with: request)
        defer { session.finishTasksAndInvalidate() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // Installed on the queue before the task starts, so every callback finds it.
                transfer.queue.addOperation {
                    transfer.continuation = continuation
                    task.resume()
                }
            }
        } onCancel: {
            task.cancel()
        }
    }

    // MARK: URLSessionDataDelegate (on `queue`)

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard LookoutDownloadHosts.isAllowed(request.url) else {
            // Declining delivers the redirect itself as the response, which `didReceive` turns into this failure.
            failure = LookoutDownloadError.unexpectedHost
            completionHandler(nil)
            return
        }
        var redirected = request
        if let range = task.originalRequest?.value(forHTTPHeaderField: "Range") {
            redirected.setValue(range, forHTTPHeaderField: "Range")
        }
        completionHandler(redirected)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard failure == nil, let http = response as? HTTPURLResponse else {
            if failure == nil { failure = LookoutDownloadError.server(status: 0) }
            return completionHandler(.cancel)
        }
        switch http.statusCode {
        case 206 where Self.rangeStart(http) == offset:
            break
        case 200:
            // The whole file: start the partial over.
            (offset, received, lastReported) = (0, 0, 0)
        case 416:
            failure = RangeNotSatisfiable()
            return completionHandler(.cancel)
        default:
            failure = LookoutDownloadError.server(status: http.statusCode)
            return completionHandler(.cancel)
        }
        do {
            if !FileManager.default.fileExists(atPath: partial.path) {
                FileManager.default.createFile(atPath: partial.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: partial)
            // Anything past `offset` (an earlier write that never finished) is dropped.
            try handle.truncate(atOffset: UInt64(offset))
            try handle.seekToEnd()
            self.handle = handle
            completionHandler(.allow)
        } catch {
            failure = LookoutDownloadError.write(reason: error.localizedDescription)
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard failure == nil, let handle else { return }
        do {
            try handle.write(contentsOf: data)
        } catch {
            failure = LookoutDownloadError.write(reason: error.localizedDescription)
            return dataTask.cancel()
        }
        received += Int64(data.count)
        if received > expectedBytes {
            failure = LookoutDownloadError.incomplete
            return dataTask.cancel()
        }
        if received - lastReported >= Self.reportInterval {
            lastReported = received
            progress(received)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle?.synchronize()
        try? handle?.close()
        handle = nil
        let result: Result<Void, Error>
        if let failure {
            result = .failure(failure)
        } else if let error = error as? URLError, error.code == .cancelled {
            result = .failure(CancellationError())
        } else if let error {
            result = .failure(LookoutDownloadError.from(error))
        } else if received != expectedBytes {
            result = .failure(LookoutDownloadError.incomplete)
        } else {
            progress(received)
            result = .success(())
        }
        continuation?.resume(with: result)
        continuation = nil
    }

    /// The first byte of a `206` response (`Content-Range: bytes 1000-1999/5000`), or nil.
    static func rangeStart(_ response: HTTPURLResponse) -> Int64? {
        guard let range = response.value(forHTTPHeaderField: "Content-Range"),
              let bytes = range.split(separator: " ").last,
              let start = bytes.split(separator: "-").first else { return nil }
        return Int64(start)
    }
}
