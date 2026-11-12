import Foundation

/// A folder's measured size, as the panel rows and totals show it.
nonisolated enum VaporMeasurement: Equatable, Sendable {
    /// Still being measured. Rows shimmer "Calculating…" and totals stay pending.
    case pending
    /// Allocated bytes on disk and the number of files (not counting folders).
    case measured(bytes: Int64, files: Int)
    /// The folder could not be read. Rows show "—"; totals treat it as zero.
    case unreadable

    var bytes: Int64 {
        if case .measured(let bytes, _) = self { return bytes }
        return 0
    }

    var files: Int {
        if case .measured(_, let files) = self { return files }
        return 0
    }

    var isPending: Bool { self == .pending }
}

/// Why a folder could not be staged for deletion. It stays in the orb with this reason on its row.
nonisolated enum VaporStagingFailure: Equatable, Sendable {
    /// macOS refused the rename (EACCES, EPERM, a locked item).
    case permissionDenied
    /// The volume can't rename the folder (EXDEV, ENOTSUP, read-only).
    case unsupportedVolume
    /// The folder no longer exists at its path.
    case missing
    /// Since it was added, the path stopped being a folder Vapor may delete: it was replaced by a
    /// symbolic link, or it now resolves into a protected location. It is left untouched.
    case changed
    /// Any other error, with its `errno` for diagnostics.
    case other(Int32)

    /// Maps a POSIX error from `rename` to the reason a row shows.
    init(errno code: Int32) {
        switch code {
        case EACCES, EPERM: self = .permissionDenied
        case ENOENT, ENOTDIR: self = .missing
        case EXDEV, ENOTSUP, EROFS: self = .unsupportedVolume
        default: self = .other(code)
        }
    }
}

/// One folder in the orb.
nonisolated struct VaporFolder: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    var classification: VaporClassification
    var measurement: VaporMeasurement
    /// Set when the last delete could not stage this folder. Cleared by the next delete attempt.
    var failure: VaporStagingFailure?

    init(id: UUID = UUID(), url: URL, classification: VaporClassification,
         measurement: VaporMeasurement = .pending, failure: VaporStagingFailure? = nil) {
        self.id = id
        self.url = url
        self.classification = classification
        self.measurement = measurement
        self.failure = failure
    }

    /// The folder's own name, as Finder shows it.
    var name: String { url.lastPathComponent }

    /// The parent folder's path with the home folder abbreviated to `~`, for the monospace row detail.
    func parentPath(home: URL) -> String {
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        if parent == homePath { return "~" }
        if parent.hasPrefix(homePath + "/") { return "~" + parent.dropFirst(homePath.count) }
        return parent
    }
}

/// Summed sizes for the header, footer, tooltip and accessibility label.
nonisolated struct VaporTotals: Equatable, Sendable {
    var count: Int
    var bytes: Int64
    var files: Int
    /// True while any folder is still being measured. Totals are shown as "calculating…".
    var isPending: Bool

    static let empty = VaporTotals(count: 0, bytes: 0, files: 0, isPending: false)

    init(count: Int, bytes: Int64, files: Int, isPending: Bool) {
        self.count = count
        self.bytes = bytes
        self.files = files
        self.isPending = isPending
    }

    init(_ folders: [VaporFolder]) {
        count = folders.count
        bytes = folders.reduce(0) { $0 + $1.measurement.bytes }
        files = folders.reduce(0) { $0 + $1.measurement.files }
        isPending = folders.contains { $0.measurement.isPending }
    }
}
