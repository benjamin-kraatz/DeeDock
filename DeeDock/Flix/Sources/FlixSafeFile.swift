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
/// Readers then read through the descriptor (``read(upTo:)``, ``mapped(maximumBytes:)``), so what
/// they decode is exactly what was checked. APIs that only take a URL (an RTFD package's file
/// wrapper) get ``url``, the checked path; those few reads keep a narrow window and are noted where
/// they happen. The descriptor closes when the value is released.
nonisolated final class FlixSafeFile: @unchecked Sendable {
    // `@unchecked`: the descriptor is only read through `pread`/`mmap`, which are thread-safe, and
    // closed once in `deinit`.
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

    /// Up to `count` bytes from the start of the file.
    func read(upTo count: Int) -> Data {
        guard !isDirectory, count > 0 else { return Data() }
        let length = Int(min(Int64(count), size))
        guard length > 0 else { return Data() }
        var data = Data(count: length)
        let read = data.withUnsafeMutableBytes { pread(descriptor, $0.baseAddress, length, 0) }
        guard read > 0 else { return Data() }
        if read < length { data.removeSubrange(read...) }
        return data
    }

    /// The whole file, memory-mapped from the descriptor, when it is at most `maximumBytes`. The
    /// mapping is private and read-only and is released with the returned data.
    func mapped(maximumBytes: Int64) -> Data? {
        guard !isDirectory, size > 0, size <= maximumBytes else { return nil }
        let length = Int(size)
        guard let pointer = mmap(nil, length, PROT_READ, MAP_PRIVATE, descriptor, 0), pointer != MAP_FAILED else {
            return nil
        }
        return Data(bytesNoCopy: pointer, count: length, deallocator: .custom { pointer, length in
            munmap(pointer, length)
        })
    }

    /// The path the kernel reports for an open descriptor.
    private static func realPath(of descriptor: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(descriptor, F_GETPATH, &buffer) != -1 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
