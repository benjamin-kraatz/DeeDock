import Darwin
import Foundation

/// The safety net under every removal. DOKK moves an item to the Trash only if this policy allows it,
/// whatever the scanner found, and checks again right before moving it.
///
/// The rules are deliberately narrow: an app bundle outside `/System` that macOS doesn't protect, or a
/// *direct* child of a known per-app data folder. Nothing deeper, nothing higher, and never one of the
/// folders themselves.
nonisolated enum AppUninstallPathPolicy {
    /// Folders in the home folder whose direct children hold per-app data.
    static let userDataFolders = [
        "Library/Containers", "Library/Group Containers", "Library/Application Scripts",
        "Library/Application Support", "Library/Caches", "Library/Preferences", "Library/Preferences/ByHost",
        "Library/Saved Application State", "Library/HTTPStorages", "Library/WebKit", "Library/Cookies",
        "Library/Logs", "Library/LaunchAgents",
    ]

    /// Folders in `/Library` whose direct children hold per-app data for all users.
    static let systemDataFolders = [
        "/Library/Application Support", "/Library/Caches", "/Library/Preferences", "/Library/LaunchAgents",
        "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools",
    ]

    /// Items directly in the home folder that a name match must never offer, whatever an app is called.
    static let protectedHomeItems: Set<String> = [
        ".Trash", ".ssh", ".gnupg", ".config", ".local", ".cache", ".zshrc", ".zprofile", ".zshenv", ".bashrc",
        ".bash_profile", ".profile", ".CFUserTextEncoding", ".DS_Store", ".localized",
    ]

    /// `SF_RESTRICTED` from `<sys/stat.h>`: System Integrity Protection guards the item.
    private static let restrictedFlag: UInt32 = 0x0008_0000

    /// Whether the app at `url` may be offered for uninstalling.
    ///
    /// Refuses anything under `/System`, items with the `restricted` flag (System Integrity Protection,
    /// such as the Safari link in `/Applications` that points into the system cryptex), apps nested in
    /// another bundle, and DOKK itself.
    /// - Parameters:
    ///   - url: The app bundle.
    ///   - ownBundle: DOKK's own bundle. Tests pass another URL.
    static func allowsApp(_ url: URL, ownBundle: URL = Bundle.main.bundleURL) -> Bool {
        guard url.isFileURL, url.pathExtension.lowercased() == "app" else { return false }
        let path = url.standardizedFileURL.path
        let resolved = url.resolvingSymlinksInPath().path
        for candidate in [path, resolved] {
            if candidate == "/System" || candidate.hasPrefix("/System/") { return false }
            // A bundle inside another bundle belongs to that bundle.
            let parents = URL(fileURLWithPath: candidate).deletingLastPathComponent().pathComponents
            if parents.contains(where: { ["app", "framework", "bundle", "appex"].contains(($0 as NSString).pathExtension.lowercased()) }) {
                return false
            }
        }
        if isRestricted(path, followingLinks: false) || isRestricted(resolved, followingLinks: true) { return false }
        if resolved == ownBundle.resolvingSymlinksInPath().path { return false }
        if let identifier = Bundle(url: url)?.bundleIdentifier, identifier.hasPrefix("de.benjaminkraatz.DeeDock") {
            return false
        }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: resolved, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Whether `url` may go to the Trash as data an uninstalled app left behind.
    ///
    /// Allowed: a direct child of one of ``userDataFolders`` (in `home`) or ``systemDataFolders``, other
    /// than hidden files such as `.DS_Store`; or a dot-folder directly in `home` that isn't one of
    /// ``protectedHomeItems``. Symbolic links aren't resolved: the Trash receives the link itself.
    static func allowsData(_ url: URL, home: URL) -> Bool {
        guard url.isFileURL else { return false }
        let item = url.standardizedFileURL
        let name = item.lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", name != "/" else { return false }
        let parent = item.deletingLastPathComponent().standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        let dataFolders = userDataFolders.map { home.appendingPathComponent($0).standardizedFileURL.path } + systemDataFolders
        if dataFolders.contains(parent) { return !name.hasPrefix(".") }
        if parent == homePath {
            return name.hasPrefix(".") && name.count > 2 && !protectedHomeItems.contains(name)
        }
        return false
    }

    private static func isRestricted(_ path: String, followingLinks: Bool) -> Bool {
        var info = stat()
        let result = followingLinks ? stat(path, &info) : lstat(path, &info)
        return result == 0 && (info.st_flags & restrictedFlag) != 0
    }
}
