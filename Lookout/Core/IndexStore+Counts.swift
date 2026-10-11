// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

/// What the index holds, for status and settings.
nonisolated extension IndexStore {
    /// Files by kind and state, and the segments and vectors they have. Codable: it travels in `LookoutIndexStatus`.
    struct Counts: Sendable, Codable, Equatable {
        /// `FileKind` raw value → state (`pending`, `done`, `partial`, `skipped`, `failed`) → files.
        var byKindAndState: [String: [String: Int]] = [:]
        var vectors = 0
        var segments = 0
        /// Long files still being read (`unfinishedCount`), and their pages and chunks left.
        var unfinished = 0
        var left = 0

        /// Every file the index knows.
        var files: Int { total { _ in true } }
        /// Files with something to find besides their name: done, or long files part read.
        var searchable: Int { total { $0 == "done" || $0 == "partial" } }
        var pending: Int { total { $0 == "pending" } }

        private func total(_ state: (String) -> Bool) -> Int {
            byKindAndState.values.reduce(0) { sum, states in
                sum + states.reduce(0) { $0 + (state($1.key) ? $1.value : 0) }
            }
        }
    }

    /// The counts within `scope`.
    func counts() throws -> Counts {
        var counts = Counts()
        try db.query("SELECT kind, state, COUNT(*) FROM files WHERE 1\(scopeSQL) GROUP BY kind, state", scopeValues) {
            counts.byKindAndState[$0.text(0) ?? "?", default: [:]][$0.text(1) ?? "?"] = Int($0.int(2))
        }
        (counts.unfinished, counts.left) = try unfinishedCount()
        let inScope = scope == nil ? "" : " AND file IN (SELECT id FROM files WHERE 1\(scopeSQL))"
        try db.query("SELECT COUNT(*), COUNT(vec) FROM segments WHERE kind != 'name'\(inScope)", scopeValues) {
            counts.segments = Int($0.int(0))
            counts.vectors = Int($0.int(1))
        }
        return counts
    }
}
