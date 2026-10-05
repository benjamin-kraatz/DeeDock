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

    /// Canonical path key for one application URL.
    ///
    /// An existing path uses `realpath`, which resolves symlinks. Case is then folded unless
    /// the volume reports case-sensitive names. A missing path resolves what it can and uses
    /// the same case rule. The result is cached so later view updates do not resolve again.
    static func key(for url: URL) -> String {
        let lookup = url.standardizedFileURL.path
        if let cached = cache.withLock({ $0[lookup] }) { return cached }
        let key = resolve(url)
        cache.withLock { $0[lookup] = key }
        return key
    }

    private static func resolve(_ url: URL) -> String {
        let path = filesystemCanonicalPath(url.standardizedFileURL.path)
            ?? url.resolvingSymlinksInPath().standardizedFileURL.path
        let resolved = URL(fileURLWithPath: path)
        guard !resolved.volumeReportsCaseSensitiveNames else { return resolved.path }
        return resolved.path.lowercased(with: posix)
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
