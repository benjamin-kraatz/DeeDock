import Foundation

/// Which paths Flix Files may touch on disk without making macOS ask.
///
/// macOS protects Desktop, Documents, Downloads, iCloud Drive, cloud storage, and other volumes:
/// the first read from DOKK shows a Files and Folders prompt. Flix Files never lets background work
/// cause one. A protected path is readable only inside a folder you allowed from Settings or the
/// panel's **Allow…** card, or one Lookout's setup already read with your permission (macOS grants
/// per app, so DOKK has it too). Everything else — thumbnails, file icons, existence checks, the
/// folder watcher — asks this policy first and falls back to Spotlight's metadata and type icons.
///
/// A value snapshot, safe to hand to background work. Rebuilt when settings change.
nonisolated struct FlixReadPolicy: Equatable, Sendable {
    let home: String
    /// Standardized roots known to be readable.
    let allowedRoots: [String]

    init(home: String = NSHomeDirectory(), allowedRoots: [String]) {
        self.home = FlixPaths.standardized(home)
        self.allowedRoots = allowedRoots.map(FlixPaths.standardized)
    }

    /// From Flix's own grants plus Lookout's indexed folders.
    init(settings: FlixSettings, lookoutFolders: [String], home: String = NSHomeDirectory()) {
        let flix = settings.watchedFolders.filter { $0.access == .allowed }.map(\.path)
        self.init(home: home, allowedRoots: flix + lookoutFolders)
    }

    /// Whether reading `path` may make macOS show its prompt.
    func isProtected(_ path: String) -> Bool {
        LookoutFolderChoice.needsPrompt(path, home: home)
    }

    /// Whether `path` can be read without a prompt.
    func canRead(_ path: String) -> Bool {
        let path = FlixPaths.standardized(path)
        guard isProtected(path) else { return true }
        return allowedRoots.contains { path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
    }

    /// Asks macOS for a folder by listing it. Only call from an explicit request: for a protected
    /// folder this shows the Files and Folders prompt and waits for the answer. Runs on a dispatch
    /// queue because the read blocks while the prompt is up.
    static func requestAccess(_ path: String) async -> FlixFolderAccessState {
        switch await LookoutLiveFolderInspector().access(path) {
        case .allowed: .allowed
        case .missing: .missing
        case .denied, .unknown, .checking: .denied
        }
    }
}
