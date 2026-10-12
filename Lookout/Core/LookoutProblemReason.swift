import Foundation

/// Why a file Lookout tried to read was skipped or failed, sorted from the reason the index stores with it
/// (`files.detail`: the gate's, the extractors' and the indexer's own words). The progress shows these counts
/// (`IndexStore.Counts.problems`); the stored words themselves can name a file, so they never leave the index.
///
/// Raw values travel in the service's status, so they're stable tokens.
nonisolated enum LookoutProblemReason: String, CaseIterable, Codable, Sendable {
    /// A picture smaller than `IndexOptions.minImageSide` (an icon, a thumbnail).
    case tooSmall
    /// Over `QueuedFileGate.maxReadBytes`.
    case tooLarge
    /// A PDF or document with a password.
    case passwordProtected
    /// A PDF or document with no text and no pages to read.
    case noText
    /// An iCloud or cloud storage file that isn't downloaded: reading it would download it.
    case notDownloaded
    /// Left out by the settings or the folder rules since it was queued (a skipped type or folder, a key or password
    /// file, a link, a file outside the chosen folders). The next sync usually removes it from the index.
    case excluded
    /// It couldn't be opened or decoded.
    case unreadable
    /// Anything else, such as the model failing on one file.
    case other

    /// Which stored reasons mean which problem, by how the stored words start. The first match wins; what matches
    /// none is `unreadable` for a file that failed without a reason, and `other` otherwise. Kept as data so the
    /// service can count them in SQL (`sqlCase`).
    static let rules: [(prefix: String, reason: LookoutProblemReason)] = [
        ("small image", .tooSmall),
        ("too large to read", .tooLarge),
        ("password-protected", .passwordProtected),
        ("no text", .noText),
        ("no pages", .noText),
        ("in the cloud", .notDownloaded),
        ("excluded", .excluded),
        ("key or password file", .excluded),
        ("outside the chosen folders", .excluded),
        ("hidden folder", .excluded),
        ("developer folder", .excluded),
        (".noindex folder", .excluded),
        ("~/Library", .excluded),
        ("link or special file", .excluded),
        ("not where it was found", .excluded),
        ("unreadable", .unreadable),
        ("can't decode", .unreadable),
        ("not an image", .unreadable),
        ("not a web archive", .unreadable),
        ("web archive without a page", .unreadable),
        ("Error Domain=", .unreadable),   // the Cocoa text system couldn't read a document
    ]

    /// The problem for a file in `state` (`skipped` or `failed`) with the stored reason `detail`.
    static func classify(state: String, detail: String?) -> LookoutProblemReason {
        let detail = detail ?? ""
        for rule in rules where detail.hasPrefix(rule.prefix) { return rule.reason }
        return state == "failed" && detail.isEmpty ? .unreadable : .other
    }

    /// `classify` as an SQL expression over the `files` table's `state` and `detail`, for counting in one query.
    static var sqlCase: String {
        func literal(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "''") + "'" }
        let whens = rules.map { rule in
            // `substr` (in characters) compares the prefix exactly: LIKE would treat `_` and `%` specially and fold
            // case.
            "WHEN substr(coalesce(detail, ''), 1, \(rule.prefix.count)) = \(literal(rule.prefix)) "
                + "THEN \(literal(rule.reason.rawValue))"
        }
        let fallback = "WHEN state = 'failed' AND coalesce(detail, '') = '' THEN \(literal(unreadable.rawValue))"
        return "CASE " + (whens + [fallback]).joined(separator: " ") + " ELSE \(literal(other.rawValue)) END"
    }
}
