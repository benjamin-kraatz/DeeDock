// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

import Foundation

/// The excerpt a segment stores for result lists.
nonisolated enum Excerpt {
    /// One line, at most `limit` characters.
    static func line(_ text: String, limit: Int = 240) -> String {
        let line = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return line.count > limit ? String(line.prefix(limit)) + "…" : line
    }
}
