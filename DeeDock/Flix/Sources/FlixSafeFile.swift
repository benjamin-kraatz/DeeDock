import Foundation

/// A file opened for a background read only after the read policy allowed it, at the place the
/// policy checked, never through a symbolic link.
///
/// Background readers (the sensitive scanner, captions and facts, Ask Robi's file reading, upload
/// conversions) queue an item and read it later. Between the two, a component of its path could be
/// swapped for a link into a protected folder. ``open(_:policy:)`` closes that gap:
/// 1. the policy resolves the path again now (``FlixReadPolicy/resolve(_:)``), checking every
///    place on the way, and refuses anything that leads into a folder DOKK was not allowed;
/// 2. the resolved path is opened with `O_NOFOLLOW_ANY`, so if any component became a link since
///    step 1, the open fails instead of following it;
/// 3. the descriptor's real path (`F_GETPATH`) is checked against the policy once more.
///
/// Readers then read through the descriptor (``read(upTo:)``, ``contents(maximumBytes:)``), so what
/// they decode is exactly what was checked. APIs that only take a URL (an RTFD package's file
/// wrapper) get ``url``, the checked path; those few reads keep a narrow window and are noted where
/// they happen. The descriptor closes when the value is released.
///
/// Bytes are always copied into memory the reader owns, never mapped. A mapping stays backed by
/// the file: if a network share disconnects or another app rewrites or truncates the file while a
/// decoder walks the mapping, the next page fault raises `SIGBUS` and the whole app crashes. A
/// copied read fails with an error instead (``ReadError``), which every reader treats as "could
/// not read this file". Each use names its own size cap, so a background read never holds more
/// than that cap in memory.
nonisolated final class FlixSafeFile: @unchecked Sendable {
    // `@unchecked`: the descriptor is only read through `pread`, which is thread-safe, and closed
    // once in `deinit`.
    let descriptor: Int32
    /// The real, link-free path that was opened.
    let path: String
    let size: Int64
    let isDirectory: Bool
    /// The file's modification date at open.
    let modified: Date

    var url: URL { URL(fileURLWithPath: path, isDirectory: isDirectory) }

    private init(descriptor: Int32, path: String, info: stat) {
        self.descriptor = descriptor
        self.path = path
        size = Int64(info.st_size)
        isDirectory = info.st_mode & S_IFMT == S_IFDIR
        modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)
                        + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
    }

    deinit { close(descriptor) }

    /// Opens `path` for reading when `policy` allows it, without following any link. Nil when the
    /// policy refuses, a link appeared since the check, or the file cannot be opened.
    static func open(_ path: String, policy: FlixReadPolicy) -> FlixSafeFile? {
        guard let resolved = policy.resolve(path) else { return nil }
        let descriptor = Darwin.open(resolved, O_RDONLY | O_NOFOLLOW_ANY | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        var info = stat()
        guard fstat(descriptor, &info) == 0, let real = realPath(of: descriptor),
              policy.spellingIsReadable(real) else {
            close(descriptor)
            return nil
        }
        let type = info.st_mode & S_IFMT
        guard type == S_IFREG || type == S_IFDIR else {
            // FIFOs, devices, and sockets are never read: a read could block or never end.
            close(descriptor)
            return nil
        }
        return FlixSafeFile(descriptor: descriptor, path: real, info: info)
    }

    /// Why ``contents(maximumBytes:)`` returned no bytes.
    nonisolated enum ReadError: Error, Equatable {
        /// A folder has no bytes to read.
        case directory
        case empty
        /// Larger than the caller's cap; nothing was read.
        case tooLarge
        /// The file became shorter while it was read (rewritten or truncated in place).
        case truncated
        /// `pread` failed, with its `errno` (a share that went away reports `EIO` or `ENXIO`).
        case failed(Int32)
        /// The reading task was cancelled between chunks.
        case cancelled
    }

    /// Bytes read per `pread` call, so a cancelled task stops within one chunk on a slow share.
    static let chunkBytes = 4 * 1_024 * 1_024

    /// Up to `count` bytes from the start of the file, copied into memory. Shorter when the file is
    /// (or became) shorter; empty when it cannot be read.
    func read(upTo count: Int) -> Data {
        guard !isDirectory, count > 0 else { return Data() }
        let length = Int(min(Int64(count), size))
        guard length > 0 else { return Data() }
        return (try? readPrefix(length)) ?? Data()
    }

    /// The whole file, copied into memory, when it is at most `maximumBytes`.
    ///
    /// - Throws: ``ReadError``: the file is a folder, empty, over the cap, became shorter than it
    ///   was at open, could not be read, or the task was cancelled. Never a crash: a share that
    ///   disconnects mid-read makes `pread` fail, and that failure is returned.
    func contents(maximumBytes: Int64) throws(ReadError) -> Data {
        guard !isDirectory else { throw .directory }
        guard size > 0 else { throw .empty }
        guard size <= maximumBytes, size <= Int64(Int.max) else { throw .tooLarge }
        let data = try readPrefix(Int(size))
        guard data.count == Int(size) else { throw .truncated }
        return data
    }

    /// Reads `length` bytes from offset 0 in chunks, retrying interrupted calls. Stops early at the
    /// end of the file (the result is then shorter).
    private func readPrefix(_ length: Int) throws(ReadError) -> Data {
        var data = Data(count: length)
        var offset = 0
        var failure: ReadError?
        data.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            while offset < length {
                if Task.isCancelled { failure = .cancelled; return }
                let wanted = min(Self.chunkBytes, length - offset)
                let read = pread(descriptor, base + offset, wanted, off_t(offset))
                if read > 0 {
                    offset += read
                } else if read == 0 {
                    return
                } else if errno != EINTR {
                    failure = .failed(errno)
                    return
                }
            }
        }
        if let failure { throw failure }
        if offset < length { data.removeSubrange(offset...) }
        return data
    }

    /// The path the kernel reports for an open descriptor.
    private static func realPath(of descriptor: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(descriptor, F_GETPATH, &buffer) != -1 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
