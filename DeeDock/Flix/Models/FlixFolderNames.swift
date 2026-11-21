import Foundation
import Synchronization

/// Folder names for display ("· Downloads", "Move to Invoices"), without touching the disk.
///
/// `FileManager.displayName(atPath:)` reads the folder's metadata. Flix Files names folders while
/// drawing rows, menus, and toasts on the main actor, and a folder on a network share that went away
/// can make that read wait for seconds, freezing the dock. So names here come from the path's
/// spelling: the last component, which is the folder's name in Finder except for the folders macOS
/// localizes. Those (Desktop, Documents, Downloads, and the other folders in your home) are looked
/// up once, off the main actor, by ``warm(policy:)``; until then, and for every other folder, the
/// spelled name stands.
nonisolated enum FlixFolderNames {
    /// The home folders macOS shows under a localized name ("Schreibtisch" for Desktop in German).
    static let localizedHomeFolders = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public",
                                       "Applications", "Library"]

    /// Localized names by standardized path, filled by ``warm(policy:)``.
    private static let localized = Mutex<[String: String]>([:])

    /// The name to show for `path`. Pure: never reads the disk.
    static func displayName(of path: String) -> String {
        let standardized = FlixPaths.standardized(path)
        if let name = localized.withLock({ $0[standardized] }) { return name }
        let name = (standardized as NSString).lastPathComponent
        return name.isEmpty ? standardized : name
    }

    /// Reads the localized names of the folders in ``localizedHomeFolders`` (and the home folder
    /// itself) that `policy` lets Flix Files read, each once per launch. Off the main actor. A
    /// protected folder (Desktop, Documents, Downloads) is looked up only once it is allowed, so this
    /// can never make macOS ask; until then its spelled name shows. Call again when the policy changes.
    @concurrent static func warm(policy: FlixReadPolicy) async {
        let home = policy.home
        let known = localized.withLock { Set($0.keys) }
        var names: [String: String] = [:]
        for path in [home] + localizedHomeFolders.map({ home + "/" + $0 }) where !known.contains(path) {
            guard !Task.isCancelled, policy.canRead(path) else { continue }
            names[path] = FileManager.default.displayName(atPath: path)
        }
        guard !names.isEmpty else { return }
        localized.withLock { $0.merge(names) { _, new in new } }
    }
}
