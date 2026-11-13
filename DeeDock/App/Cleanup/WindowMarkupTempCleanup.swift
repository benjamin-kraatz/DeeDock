import Darwin
import Foundation
import OSLog

/// Deletes the window pictures that dragging a markup out left in the temporary folder.
///
/// A drag to Finder asks ``WindowMarkupExport/dragProvider(png:filename:)`` for a file, which
/// writes a PNG of the window to `$TMPDIR/DeeDockMarkup-<UUID>/`. The drop target copies it, but
/// nothing tells DOKK when it's done reading, so the folder is swept later: when the next export
/// writes one, and once at launch.
///
/// The sweep looks only at direct children of the temporary folder named `DeeDockMarkup-<UUID>`,
/// and only at real directories (checked with `lstat`, so a link is never followed) owned by the
/// current user. A folder younger than ``gracePeriod`` is left, so a drop target still reading it
/// isn't broken.
nonisolated struct WindowMarkupTempCleanup {
    /// The name every export folder starts with, followed by a UUID.
    static let folderPrefix = "DeeDockMarkup-"

    /// How long a drop target has to read an exported picture before it's swept.
    static let gracePeriod: TimeInterval = 5 * 60

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DOKK", category: "Cleanup")

    private let directory: URL
    private let now: () -> Date

    /// - Parameters:
    ///   - directory: The folder holding export folders. Tests pass a temporary one.
    ///   - now: The clock for the grace period.
    init(directory: URL = FileManager.default.temporaryDirectory, now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.now = now
    }

    /// Sweeps off the main actor at utility priority. The task is not retained: it finishes in
    /// moments, and anything it misses is swept the next time.
    static func runInBackground() {
        Task.detached(priority: .utility) { WindowMarkupTempCleanup().run() }
    }

    /// Deletes every export folder older than the grace period.
    /// - Returns: How many folders were deleted.
    @discardableResult
    func run() -> Int {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return 0 }
        let cutoff = now().addingTimeInterval(-Self.gracePeriod)
        var removed = 0
        for name in names where Self.isExportFolderName(name) {
            let url = directory.appendingPathComponent(name, isDirectory: true)
            // This is a delete path: only a real directory DOKK could have made is removed.
            var info = stat()
            guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == getuid() else { continue }
            let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
            guard modified < cutoff else { continue }
            do {
                try FileManager.default.removeItem(at: url)
                removed += 1
            } catch {
                Self.logger.error("Could not delete a markup export folder: \(error.localizedDescription, privacy: .public)")
            }
        }
        return removed
    }

    /// `DeeDockMarkup-` followed by exactly a UUID, as the export names its folders.
    static func isExportFolderName(_ name: String) -> Bool {
        guard name.hasPrefix(folderPrefix) else { return false }
        return UUID(uuidString: String(name.dropFirst(folderPrefix.count))) != nil
    }
}
