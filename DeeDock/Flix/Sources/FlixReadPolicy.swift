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
/// The check follows symbolic links without ever touching what they point to first: a link in an
/// allowed folder that points into a protected one is as unreadable as the protected path itself,
/// because every read through it (metadata, extended attributes, thumbnails, file contents,
/// conversions) would reach the protected folder. See ``canRead(_:)``.
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

    /// Whether `path` can be read without a prompt, following any symbolic links on the way.
    ///
    /// The spelling is checked first, without touching the disk. Then the path is resolved one
    /// component at a time, as `realpath` would, but each component is examined with `lstat` only
    /// once the place it leads to is known to be readable: the component is readable by spelling,
    /// or it is an ancestor of the readable destination. A symbolic link is read with `readlink`
    /// (the link itself lives in readable territory), its target is spliced into the rest of the
    /// path, and the new destination must be readable by spelling before anything under it is
    /// examined. ".." is resolved against the components already examined, which are real
    /// directories. At most ``maximumLinkHops`` links are followed. A component that cannot be
    /// examined (permission denied) makes the path unreadable; a missing one ends the walk, since
    /// nothing further can be followed and the spelling decides.
    func canRead(_ path: String) -> Bool {
        guard path.hasPrefix("/") else { return false }
        var pending = Array(path.split(separator: "/").map(String.init).reversed())
        var resolved: [String] = []
        var hops = 0
        var destination = Self.lexical(resolved + pending.reversed())
        guard spellingIsReadable(destination) else { return false }
        while let component = pending.popLast() {
            if component == "." { continue }
            if component == ".." {
                _ = resolved.popLast()
                continue
            }
            let candidate = "/" + (resolved + [component]).joined(separator: "/")
            guard spellingIsReadable(candidate) || destination == candidate || destination.hasPrefix(candidate + "/")
            else { return false }
            var info = stat()
            guard lstat(candidate, &info) == 0 else { return errno == ENOENT || errno == ENOTDIR }
            guard info.st_mode & S_IFMT == S_IFLNK else {
                resolved.append(component)
                continue
            }
            hops += 1
            guard hops <= Self.maximumLinkHops, let target = Self.linkTarget(candidate) else { return false }
            if target.hasPrefix("/") { resolved = [] }
            pending.append(contentsOf: target.split(separator: "/").map(String.init).reversed())
            destination = Self.lexical(resolved + pending.reversed())
            guard spellingIsReadable(destination) else { return false }
        }
        return true
    }

    /// Whether the spelling of `path` alone may be read, without looking at the disk.
    func spellingIsReadable(_ path: String) -> Bool {
        let path = FlixPaths.standardized(path)
        guard isProtected(path) else { return true }
        return allowedRoots.contains { path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
    }

    /// Links followed before a path counts as unreadable (a loop, or a chain too long to trust).
    static let maximumLinkHops = 16

    /// An absolute path from components, with "." dropped and ".." applied by spelling only.
    private static func lexical(_ components: [String]) -> String {
        var result: [String] = []
        for component in components where !component.isEmpty && component != "." {
            if component == ".." { _ = result.popLast() } else { result.append(component) }
        }
        return "/" + result.joined(separator: "/")
    }

    /// A symbolic link's target as stored, without following it.
    private static func linkTarget(_ path: String) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        let length = readlink(path, &buffer, Int(PATH_MAX))
        guard length > 0 else { return nil }
        return String(decoding: buffer[0..<length].map { UInt8(bitPattern: $0) }, as: UTF8.self)
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
