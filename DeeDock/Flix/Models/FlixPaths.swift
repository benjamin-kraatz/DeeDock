import Foundation

/// Path helpers shared by the sources, the history, and the access policy.
nonisolated enum FlixPaths {
    /// An absolute path, standardized, without a trailing slash. Every stored path goes through this
    /// so the history's dedupe key is stable.
    static func standardized(_ path: String) -> String {
        let standardized = (path as NSString).standardizingPath
        return standardized.count > 1 && standardized.hasSuffix("/") ? String(standardized.dropLast()) : standardized
    }

    /// `path` for comparisons that must match the way macOS's default volumes do: case-insensitive
    /// and normalization-insensitive (`Documents`, `documents`, and a decomposed spelling are one
    /// folder). Never stored or shown; only compared.
    static func folded(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: nil)
            .precomposedStringWithCanonicalMapping
    }

    /// The page a download came from, cleaned by ``FlixURLSanitizer`` (no query, fragment, or
    /// sign-in details; nothing at all for a credential-bearing address). `whereFroms` is
    /// `kMDItemWhereFroms`: the file's own address first, then the page that linked to it. The page
    /// is preferred when present.
    ///
    /// This is what a source reports; whether any of it is stored is decided later by
    /// ``FlixSourcePolicy`` from the web-link settings.
    static func sourcePage(fromWhereFroms whereFroms: [String]) -> URL? {
        sourcePageAndIdentity(fromWhereFroms: whereFroms)?.page
    }

    /// ``sourcePage(fromWhereFroms:)`` with the address it was cleaned from (`identity`, query
    /// included), for `FlixActivityEvent.sourcePageIdentity`. Kept in memory only.
    static func sourcePageAndIdentity(fromWhereFroms whereFroms: [String]) -> (page: URL, identity: URL)? {
        let candidates = whereFroms.count > 1 ? [whereFroms[1], whereFroms[0]] : whereFroms
        for candidate in candidates {
            guard let raw = URL(string: candidate), let page = FlixURLSanitizer.sanitize(raw) else { continue }
            return (page, raw)
        }
        return nil
    }

    /// A page's host without `www.`, as the "Downloaded from …" line shows it.
    static func displayHost(of url: URL) -> String? {
        guard let host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The default watched folders: Desktop, Documents, Downloads, and iCloud Drive.
    static func defaultWatchedFolders(home: String = NSHomeDirectory()) -> [String] {
        ["Desktop", "Documents", "Downloads", "Library/Mobile Documents/com~apple~CloudDocs"].map {
            standardized(home + "/" + $0)
        }
    }

    /// `~/Downloads`, where new files count as downloads even without a source page.
    static func downloads(home: String = NSHomeDirectory()) -> String {
        standardized(home + "/Downloads")
    }
}
