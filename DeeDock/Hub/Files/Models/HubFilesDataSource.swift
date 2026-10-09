import Foundation

/// A running folder watch. Stopping it is idempotent.
@MainActor
protocol HubFilesWatch: AnyObject {
    func stop()
}

extension HubDirectoryWatcher: HubFilesWatch {}

/// Where the Files model reads folders, Recents, and free space.
///
/// The live implementation wraps the Files services; previews and tests inject an in-memory one,
/// so they never touch the file system.
@MainActor
protocol HubFilesDataSource: AnyObject {
    /// The user's home folder; the fallback location and the "~" in search paths.
    var homeDirectory: URL { get }

    /// Recently used files, newest first. Observable in the live implementation.
    var recentItems: [HubFileItem] { get }

    /// Starts or stops the Recents query. Only visible Recents panes keep it running.
    func setRecentsActive(_ active: Bool)

    /// True when `url` is an existing folder. Cheap enough for restore and fallback checks.
    func directoryExists(_ url: URL) -> Bool

    /// The folder's immediate, non-hidden children. Runs its I/O off the main actor.
    func items(in folder: URL) async throws -> [HubFileItem]

    /// One item's current metadata, or nil when it no longer exists.
    func item(at url: URL) async -> HubFileItem?

    /// Bytes available for important usage on the volume holding `url`.
    func availableCapacity(for url: URL) async -> Int64?

    /// The number of visible items in `folder`, for icon-view captions and the preview column.
    func itemCount(in folder: URL) async -> Int?

    /// Starts watching `folder`; `onChange` runs on the main actor until the watch is stopped.
    func watch(_ folder: URL, onChange: @escaping @MainActor () -> Void) -> HubFilesWatch?
}

/// The production data source over `HubDirectoryLister`, `HubDirectoryWatcher`, and `HubRecentFiles`.
@MainActor
final class HubFilesLiveDataSource: HubFilesDataSource {
    private let recents = HubRecentFiles()

    let homeDirectory = HubFilesPath.normalized(FileManager.default.homeDirectoryForCurrentUser)

    var recentItems: [HubFileItem] { recents.items }

    func setRecentsActive(_ active: Bool) {
        if active { recents.start() } else { recents.stop() }
    }

    func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    func items(in folder: URL) async throws -> [HubFileItem] {
        try await HubDirectoryLister.items(in: folder)
    }

    func item(at url: URL) async -> HubFileItem? {
        await VolumeReads.run(qos: .userInitiated) { HubDirectoryLister.item(at: url) }
    }

    func availableCapacity(for url: URL) async -> Int64? {
        await VolumeReads.run(qos: .utility) {
            let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                                                           .volumeAvailableCapacityKey])
            return values?.volumeAvailableCapacityForImportantUsage
                ?? values?.volumeAvailableCapacity.map(Int64.init)
        }
    }

    func itemCount(in folder: URL) async -> Int? {
        await VolumeReads.run(qos: .utility) {
            try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                         options: [.skipsHiddenFiles]).count
        }
    }

    func watch(_ folder: URL, onChange: @escaping @MainActor () -> Void) -> HubFilesWatch? {
        HubDirectoryWatcher(folder: folder, onChange: onChange)
    }
}
