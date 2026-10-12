import Darwin
import Foundation

/// Checks a queued file again just before the indexer reads it, and opens it so that the file checked is the file read.
///
/// The crawl's checks held when the file was queued, which can be hours before the backfill reads it. By then
/// `notes.txt` may have become a link to a key outside the chosen folders, or a folder on its way may have. Reading it
/// by path would index the target under `notes.txt`, past both the folder rules and the secret-name rules. So each file
/// is checked again, in this order:
///
/// 1. Its stored path against the settings: not a key or password file (`Rules.isSecret`), not an excluded type,
///    inside a root that's walked and not in a skipped folder there, and no hidden, developer or `.noindex` folder or
///    ~/Library on the way down from that root.
/// 2. `lstat`: a regular file, not a link, not a dataless placeholder (reading one downloads it).
/// 3. `open` with `O_NOFOLLOW`, then `fstat` on the descriptor: still a regular file, and the same one `lstat` saw.
///    `O_NONBLOCK` keeps a FIFO swapped in at the last moment from blocking the open.
/// 4. `F_GETPATH` on the descriptor: the open file is at the stored path. A folder on the way that became a link
///    between step 1 and the open shows up here as another path, which is refused unless it passes step 1 itself and
///    is the queued inode (`placeRefusal`).
/// 5. Its inode against the record. Another file at the same path (a replacement that kept the size and date) is
///    queued again with its own identity rather than read under the old row.
///
/// A package document (`Rules.packageDocuments`, an `.rtfd`) goes through the same steps as a folder: the package must
/// be a real folder, never a link, opened with `O_DIRECTORY | O_NOFOLLOW`, and it is its inode that's compared with the
/// record. The file holding its text is then opened inside that descriptor (`openat`, `O_NOFOLLOW`), so neither the
/// package nor the file in it can be a link, and the same size cap applies (`openPackage`).
///
/// The extractors then read the bytes from that descriptor (`Verdict.read`), never the path, so the check and the read
/// can't race. Devices aren't compared with the record, because an external drive gets a new device number at every
/// mount. The crawl's relevance rules (code projects, datasets) aren't repeated: they decide what's worth reading, not
/// what may be read. Nor are packages on the way looked up again, which would cost a lookup per folder for every file.
nonisolated struct QueuedFileGate: Sendable {
    /// What to do with a queued file.
    enum Verdict {
        /// Read it: these are its bytes, read from the descriptor that was checked.
        case read(Data)
        /// Another file is at the path now: queue it again as this one.
        case changed(Candidate)
        /// Don't read it. `state` is `skipped` (the crawl's reason, which a later sync settles for good) or `failed`
        /// (it couldn't be opened).
        case refused(state: String, detail: String)
    }

    /// Files larger than this aren't read: their bytes are copied into memory (`contents(of:size:)`), and a long PDF
    /// is read again for every step of its later pass. 512 MB keeps the largest scanned books.
    static let maxReadBytes = 512 << 20

    /// The real paths of the roots the last sync walked (`CrawlReport.roots`).
    let roots: [String]
    /// The skipped folders, as given and as real paths.
    let skipped: [String]
    let excludedExtensions: Set<String>
    /// The real path of the home folder, whose `Library` is never read.
    let home: String

    /// - Parameters:
    ///   - roots: The real paths of the walked roots. Files under none of them are refused.
    ///   - options: The indexing settings: skipped folders and file types.
    ///   - home: The home folder (tests pass a folder of their own).
    init(roots: [String], options: IndexOptions,
         home: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        self.roots = roots
        skipped = options.excludedFolders.flatMap { [$0, FolderSelection.realPath($0)] }
        excludedExtensions = options.excludedExtensions
        self.home = FolderSelection.realPath(Rules.normalizedFolder(home))
    }

    /// Checks `file` again and opens it (see the type's steps). Touches only the file: no database.
    func open(_ file: FileRecord) -> Verdict {
        if let reason = refusal(forPath: file.path) { return .refused(state: "skipped", detail: reason) }
        if let entry = Rules.packageDocumentEntry(URL(fileURLWithPath: file.path)) {
            return openPackage(file, entry: entry)
        }
        var linkInfo = stat()
        guard lstat(file.path, &linkInfo) == 0 else { return .refused(state: "failed", detail: Self.errorText(errno)) }
        if let reason = Self.refusal(for: linkInfo) { return .refused(state: "skipped", detail: reason) }

        let descriptor = Darwin.open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        // A link put in place after `lstat`: O_NOFOLLOW makes that open fail with ELOOP.
        guard descriptor >= 0 else {
            let error = errno
            return error == ELOOP ? .refused(state: "skipped", detail: "link or special file")
                : .refused(state: "failed", detail: Self.errorText(error))
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { return .refused(state: "failed", detail: Self.errorText(errno)) }
        guard Self.refusal(for: info) == nil, info.st_dev == linkInfo.st_dev, info.st_ino == linkInfo.st_ino else {
            return .refused(state: "skipped", detail: "link or special file")
        }
        guard let opened = Self.openPath(descriptor) else {
            return .refused(state: "failed", detail: Self.errorText(errno))
        }
        if let reason = placeRefusal(opened: opened, file: file, inode: UInt64(info.st_ino)) {
            return .refused(state: "skipped", detail: reason)
        }
        if UInt64(info.st_ino) != file.inode {
            let mtime = Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9
            return .changed(Candidate(path: file.path, kind: file.kind, size: Int64(info.st_size), mtime: mtime,
                                      inode: UInt64(info.st_ino), device: UInt64(bitPattern: Int64(info.st_dev)),
                                      lastUsed: file.lastUsed))
        }
        guard info.st_size <= Self.maxReadBytes else {
            let megabytes = Int(info.st_size >> 20)
            return .refused(state: "skipped", detail: "too large to read (\(megabytes) MB)")
        }
        do {
            return .read(try Self.contents(of: descriptor, size: Int(info.st_size)))
        } catch {
            return .refused(state: "failed", detail: "\(error)")
        }
    }

    /// `open` for a package document: the package checked as `open` checks a file (a real folder, not a link, at its
    /// stored path, the queued inode), then `entry` opened inside it and checked as a regular file with data on this
    /// Mac and within the size cap. A package replaced since the crawl (another inode) is queued again with the
    /// entry's size and date.
    private func openPackage(_ file: FileRecord, entry: String) -> Verdict {
        var linkInfo = stat()
        guard lstat(file.path, &linkInfo) == 0 else { return .refused(state: "failed", detail: Self.errorText(errno)) }
        if let reason = Self.packageRefusal(for: linkInfo) { return .refused(state: "skipped", detail: reason) }
        let directory = Darwin.open(file.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else {
            let error = errno
            return error == ELOOP || error == ENOTDIR ? .refused(state: "skipped", detail: "link or special file")
                : .refused(state: "failed", detail: Self.errorText(error))
        }
        defer { close(directory) }
        var info = stat()
        guard fstat(directory, &info) == 0 else { return .refused(state: "failed", detail: Self.errorText(errno)) }
        guard Self.packageRefusal(for: info) == nil, info.st_dev == linkInfo.st_dev, info.st_ino == linkInfo.st_ino else {
            return .refused(state: "skipped", detail: "link or special file")
        }
        guard let opened = Self.openPath(directory) else {
            return .refused(state: "failed", detail: Self.errorText(errno))
        }
        if let reason = placeRefusal(opened: opened, file: file, inode: UInt64(info.st_ino)) {
            return .refused(state: "skipped", detail: reason)
        }
        let descriptor = openat(directory, entry, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            let error = errno
            return error == ELOOP ? .refused(state: "skipped", detail: "link or special file")
                : .refused(state: "failed", detail: Self.errorText(error))
        }
        defer { close(descriptor) }
        var inner = stat()
        guard fstat(descriptor, &inner) == 0 else { return .refused(state: "failed", detail: Self.errorText(errno)) }
        if let reason = Self.refusal(for: inner) { return .refused(state: "skipped", detail: reason) }
        if UInt64(info.st_ino) != file.inode {
            let mtime = Double(inner.st_mtimespec.tv_sec) + Double(inner.st_mtimespec.tv_nsec) / 1e9
            return .changed(Candidate(path: file.path, kind: file.kind, size: Int64(inner.st_size), mtime: mtime,
                                      inode: UInt64(info.st_ino), device: UInt64(bitPattern: Int64(info.st_dev)),
                                      lastUsed: file.lastUsed))
        }
        guard inner.st_size <= Self.maxReadBytes else {
            let megabytes = Int(inner.st_size >> 20)
            return .refused(state: "skipped", detail: "too large to read (\(megabytes) MB)")
        }
        do {
            return .read(try Self.contents(of: descriptor, size: Int(inner.st_size)))
        } catch {
            return .refused(state: "failed", detail: "\(error)")
        }
    }

    /// Why a package with this `stat` isn't read, or nil for a real folder with its data on this Mac.
    private static func packageRefusal(for info: stat) -> String? {
        guard (info.st_mode & S_IFMT) == S_IFDIR else { return "link or special file" }
        if info.st_flags & 0x4000_0000 != 0 { return "in the cloud, not downloaded" }   // SF_DATALESS
        return nil
    }

    /// Why the file open at `opened` (its `F_GETPATH`) may not be read for `file`'s row, or nil. Usually it's the stored
    /// path. Another path means a case-only rename on a case-insensitive volume, a hard link the kernel names
    /// differently, or a folder on the way swapped for a link. On a case-sensitive volume that link may lead to a
    /// sibling spelled the same but for case (`Notes` → `NOTES`), so paths are never compared by spelling. Another path
    /// must itself pass the settings and folder rules (`refusal(forPath:)`), and the file must be the very one the crawl
    /// queued (the same inode).
    func placeRefusal(opened: String, file: FileRecord, inode: UInt64) -> String? {
        guard opened != file.path else { return nil }
        if let reason = refusal(forPath: opened) { return reason }
        return inode == file.inode ? nil : "not where it was found: a folder on its way moved or is a link"
    }

    /// Why the settings no longer allow reading `path`, or nil. String checks only, so it costs nothing.
    func refusal(forPath path: String) -> String? {
        let name = (path as NSString).lastPathComponent
        if Rules.isSecret(name) { return "key or password file" }
        if excludedExtensions.contains((name as NSString).pathExtension.lowercased()) { return "excluded type" }
        // Any root that holds the file may allow it: a folder chosen inside a skipped one is walked whole. The
        // closest root's reason is the one reported.
        let holding = roots.filter { FolderSelection.isInside(path, $0) }.sorted { $0.count > $1.count }
        guard !holding.isEmpty else { return "outside the chosen folders" }
        var reasons: [String] = []
        for root in holding {
            guard let reason = refusal(forPath: path, under: root) else { return nil }
            reasons.append(reason)
        }
        return reasons[0]
    }

    /// Why the crawl wouldn't have reached `path` from `root`: a skipped folder, or a folder on the way it never walks
    /// into.
    private func refusal(forPath path: String, under root: String) -> String? {
        guard FolderSelection.isSearched(path, folders: [root], skipped: skipped) else { return "excluded folder" }
        let between = path.dropFirst(root.count + 1).split(separator: "/").dropLast()
        var folder = root
        for component in between {
            folder += "/" + component
            if component.hasPrefix(".") { return "hidden folder" }
            if let reason = Rules.skipReason(forFolder: URL(fileURLWithPath: folder), home: home, excluded: []) {
                return reason
            }
        }
        return nil
    }

    /// Why a file with this `stat` isn't read, or nil for a regular file with its data on this Mac.
    private static func refusal(for info: stat) -> String? {
        guard (info.st_mode & S_IFMT) == S_IFREG else { return "link or special file" }
        // Reading a dataless placeholder (iCloud "Optimize Mac Storage", File Providers) downloads it.
        if info.st_flags & 0x4000_0000 != 0 { return "in the cloud, not downloaded" }   // SF_DATALESS
        return nil
    }

    /// The path of the file open at `descriptor`, as the kernel knows it (a real path, like the crawl's).
    private static func openPath(_ descriptor: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(descriptor, F_GETPATH, &buffer) != -1 else { return nil }
        return String(cString: buffer)
    }

    /// The file's bytes, read from the descriptor in 8 MB pieces with `pread`. Never memory-mapped, by design: a
    /// mapped file that's cut shorter while it's read faults the reading thread with SIGBUS and takes the service down.
    /// A read only ever returns fewer bytes. A file cut shorter after `fstat` yields what's left, and the extractor
    /// fails on it or reads it; one that grew yields its first `size` bytes. Handing PDFKit or ImageIO a URL, even
    /// `/dev/fd/<n>`, wouldn't avoid this, as they may map a file they open themselves.
    ///
    /// - Throws: `ReadFailure` when a read fails.
    static func contents(of descriptor: Int32, size: Int) throws -> Data {
        guard size > 0 else { return Data() }
        var data = Data(count: size)
        var total = 0
        try data.withUnsafeMutableBytes { buffer in
            while total < size {
                let read = pread(descriptor, buffer.baseAddress! + total, min(size - total, 8 << 20), off_t(total))
                if read < 0, errno == EINTR { continue }
                guard read >= 0 else { throw ReadFailure(errorText(errno)) }
                if read == 0 { break }   // cut shorter since `fstat`: read what's there
                total += read
            }
        }
        if total < size { data.count = total }
        return data
    }

    private static func errorText(_ error: Int32) -> String {
        "unreadable: \(String(cString: strerror(error)))"
    }

    /// A read that failed after the checks passed.
    struct ReadFailure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
