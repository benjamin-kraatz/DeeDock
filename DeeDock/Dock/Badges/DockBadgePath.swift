import Darwin
import Foundation
import os

/// Installation identity shared by the Dock badge snapshot and the tile lookup.
///
/// `standardizedFileURL` leaves a pin at `/Applications/Safari.app` distinct from the Dock item
/// at `/System/Applications/Safari.app`, and it preserves case. Both sides call `key(for:)`.
nonisolated enum DockBadgePath {
    private static let cache = OSAllocatedUnfairLock(initialState: [String: String]())
    private static let posix = Locale(identifier: "en_US_POSIX")

    /// Resolved path for one application URL.
    ///
    /// An existing path uses `realpath`, which resolves symlinks and keeps the volume's on-disk
    /// spelling. A missing path keeps the spelling it was given. Nothing here lowercases a name.
    /// The result is cached so later view updates do not resolve again.
    static func key(for url: URL) -> String {
        let lookup = url.standardizedFileURL.path
        if let cached = cache.withLock({ $0[lookup] }) { return cached }
        let key = resolve(url)
        cache.withLock { $0[lookup] = key }
        return key
    }

    /// Saved history key for records that already name one installation.
    ///
    /// A symlink or firmlink adopts `identity`. A case-only difference keeps a stored spelling,
    /// so the visible app name is not rewritten in lowercase.
    static func preferredStorageKey(identity: String, stored: [String]) -> String {
        let changed = stored.contains { !samePath($0, identity) }
        if changed { return identity }
        if stored.contains(identity) { return identity }
        return stored.sorted().first ?? identity
    }

    /// True when both paths are one installation.
    ///
    /// Symlinks compare equal after resolution. On a volume that is not case-sensitive, spellings
    /// that differ only by case compare equal without changing either string.
    static func sameInstallation(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        let left = key(for: URL(fileURLWithPath: lhs))
        let right = key(for: URL(fileURLWithPath: rhs))
        if left == right { return true }
        return samePath(left, right) || samePath(lhs, rhs)
    }

    private static func resolve(_ url: URL) -> String {
        if let canonical = filesystemCanonicalPath(url.standardizedFileURL.path) { return canonical }
        return url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func samePath(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        guard !URL(fileURLWithPath: lhs).volumeReportsCaseSensitiveNames else { return false }
        return lhs.compare(rhs, options: [.caseInsensitive], locale: posix) == .orderedSame
    }

    /// `realpath` allocates the buffer when the second argument is `nil`.
    private static func filesystemCanonicalPath(_ path: String) -> String? {
        path.withCString { pointer in
            guard let resolved = realpath(pointer, nil) else { return nil }
            defer { free(resolved) }
            return String(cString: resolved)
        }
    }
}
