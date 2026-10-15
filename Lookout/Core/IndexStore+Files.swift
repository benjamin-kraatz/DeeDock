// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

import Foundation

/// The `files` rows: what's indexed, its state, and what's waiting.
nonisolated extension IndexStore {
    static let fileColumns = "id, path, kind, size, mtime, inode, device, state, last_used"

    /// The order of the first pass: the most recently used first (Spotlight's last-used date, else the modification
    /// date), then screenshots, images, PDFs and documents.
    static let pendingOrderSQL = "coalesce(last_used, mtime) DESC, \(FileKind.kindOrderSQL)"

    static func record(_ row: Database.Statement) -> FileRecord {
        FileRecord(id: row.int(0), path: row.text(1) ?? "", kind: FileKind(rawValue: row.text(2) ?? "") ?? .doc,
                   size: row.int(3), mtime: row.double(4), inode: UInt64(bitPattern: row.int(5)),
                   device: UInt64(bitPattern: row.int(6)), state: row.text(7) ?? "pending",
                   lastUsed: row.isNull(8) ? nil : row.double(8))
    }

    /// Every file under one of `roots`.
    func files(under roots: [String]) throws -> [FileRecord] {
        var out: [FileRecord] = []
        // A folder inside another one listed is already covered (each file once).
        for root in roots where !roots.contains(where: { FolderSelection.isInside(root, $0) }) {
            let prefix = root.hasSuffix("/") ? root : root + "/"
            // A range on the UNIQUE path index: everything that starts with `prefix`.
            try db.query("SELECT \(Self.fileColumns) FROM files WHERE path >= ? AND path < ?",
                         [.text(prefix), .text(prefix + "\u{10FFFF}")]) { out.append(Self.record($0)) }
        }
        return out
    }

    /// The file at `path`, if the index has it.
    func file(at path: String) throws -> FileRecord? {
        var found: FileRecord?
        try db.query("SELECT \(Self.fileColumns) FROM files WHERE path = ?", [.text(path)]) { found = Self.record($0) }
        return found
    }

    /// Adds a file (pending) and returns its id.
    @discardableResult
    func insert(_ file: Candidate) throws -> Int64 {
        try db.run("INSERT INTO files(path, kind, size, mtime, inode, device, last_used) VALUES(?, ?, ?, ?, ?, ?, ?)",
                   [.text(file.path), .text(file.kind.rawValue), .int(file.size), .double(file.mtime),
                    .int(Int64(bitPattern: file.inode)), .int(Int64(bitPattern: file.device)), .optional(file.lastUsed)])
        let id = db.lastInsertID
        try addNameRow(file: id, path: file.path)
        return id
    }

    /// The file changed on disk: drop what was extracted from it and queue it again.
    func requeue(_ id: Int64, as file: Candidate) throws {
        try deleteSegments(of: id, keepingName: true)
        try db.run("""
            UPDATE files SET kind = ?, size = ?, mtime = ?, inode = ?, device = ?, last_used = ?, state = 'pending',
                detail = NULL, info = NULL, indexed_at = NULL WHERE id = ?
            """, [.text(file.kind.rawValue), .int(file.size), .double(file.mtime), .int(Int64(bitPattern: file.inode)),
                  .int(Int64(bitPattern: file.device)), .optional(file.lastUsed), .int(id)])
    }

    /// Extract and embed the file again, as it is (after a better way to read it arrived).
    func requeue(_ id: Int64) throws {
        try deleteSegments(of: id, keepingName: true)
        try db.run("UPDATE files SET state = 'pending', detail = NULL, info = NULL, indexed_at = NULL WHERE id = ?",
                   [.int(id)])
    }

    /// Same inode, size and date at a new path: a move or rename. Only the path (and its keyword row) changes; nothing
    /// is re-embedded. (Screenshot tools move screenshots into project folders all the time.)
    func move(_ id: Int64, to path: String) throws {
        try db.run("UPDATE files SET path = ? WHERE id = ?", [.text(path), .int(id)])
        try db.run("""
            UPDATE fts SET name = ?, body = ? WHERE rowid IN (SELECT id FROM segments WHERE file = ? AND kind = 'name')
            """, [.text(SearchText.normalized(Self.nameText(path))), .text(SearchText.normalized(Self.folderText(path))),
                  .int(id)])
    }

    /// Records the device number a file's volume has now (it changes at every mount), without reading it again.
    func setDevice(_ id: Int64, _ device: UInt64) throws {
        try db.run("UPDATE files SET device = ? WHERE id = ?", [.int(Int64(bitPattern: device)), .int(id)])
    }

    /// Records a newer last-used date for a file whose contents didn't change (it moves up the queue if it's pending).
    func setLastUsed(_ id: Int64, _ lastUsed: Double?) throws {
        try db.run("UPDATE files SET last_used = ? WHERE id = ?", [.optional(lastUsed), .int(id)])
    }

    /// Removes a file, its segments and its keyword rows.
    func delete(_ id: Int64) throws {
        try db.run("DELETE FROM fts WHERE rowid IN (SELECT id FROM segments WHERE file = ?)", [.int(id)])
        try db.run("DELETE FROM files WHERE id = ?", [.int(id)])
    }

    /// Removes every file that isn't under one of `roots` (folders taken out of the app). Returns how many went.
    @discardableResult
    func prune(keepingUnder roots: [String]) throws -> Int {
        let prefixes = roots.map { $0.hasSuffix("/") ? $0 : $0 + "/" }
        var gone: [Int64] = []
        try db.query("SELECT id, path FROM files") { row in
            let path = row.text(1) ?? ""
            if !prefixes.contains(where: { path.hasPrefix($0) }) { gone.append(row.int(0)) }
        }
        guard !gone.isEmpty else { return 0 }
        try db.transaction {
            for id in gone { try delete(id) }
        }
        return gone.count
    }

    /// Queues every file again and forgets the fingerprint (after the model or settings changed). Names stay
    /// searchable meanwhile.
    func resetAll() throws {
        try db.transaction {
            try db.run("DELETE FROM fts WHERE rowid IN (SELECT id FROM segments WHERE kind != 'name')")
            try db.run("DELETE FROM segments WHERE kind != 'name'")
            try db.run("UPDATE files SET state = 'pending', detail = NULL, info = NULL, indexed_at = NULL")
            try setMeta("fingerprint", nil)
        }
    }

    /// Files waiting to be embedded, in the first pass's order (`pendingOrderSQL`); `only` narrows it to some files
    /// (just-added ones).
    func pending(limit: Int?, only ids: Set<Int64>? = nil) throws -> [FileRecord] {
        var out: [FileRecord] = []
        if let ids, ids.isEmpty { return out }
        let filter = ids.map { " AND id IN (\($0.map(String.init).joined(separator: ",")))" } ?? ""
        try db.query("""
            SELECT \(Self.fileColumns) FROM files WHERE state = 'pending'\(filter)\(scopeSQL)
            ORDER BY \(Self.pendingOrderSQL) LIMIT ?
            """, scopeValues + [.int(Int64(limit ?? -1))]) { out.append(Self.record($0)) }
        return out
    }

    func pendingCount() throws -> Int {
        var count = 0
        try db.query("SELECT COUNT(*) FROM files WHERE state = 'pending'\(scopeSQL)", scopeValues) {
            count = Int($0.int(0))
        }
        return count
    }

    /// Long files with pages or chunks still to read after their first step, in `pending`'s order.
    func unfinished() throws -> [FileRecord] {
        var out: [FileRecord] = []
        try db.query("""
            SELECT \(Self.fileColumns) FROM files WHERE state = 'partial'\(scopeSQL)
            ORDER BY \(Self.pendingOrderSQL)
            """, scopeValues) { out.append(Self.record($0)) }
        return out
    }

    /// How many long files are unfinished, and how many of their pages and chunks are left to read.
    func unfinishedCount() throws -> (files: Int, left: Int) {
        var count = (files: 0, left: 0)
        try db.query("""
            SELECT COUNT(*), SUM(MAX(0, CAST(json_extract(info, '$.read_end') AS INTEGER)
                                      - CAST(json_extract(info, '$.read_to') AS INTEGER)))
            FROM files WHERE state = 'partial'\(scopeSQL)
            """, scopeValues) { count = (Int($0.int(0)), Int($0.int(1))) }
        return count
    }

    /// What indexing learned about a file (`finish`'s `info`).
    func info(of id: Int64) throws -> [String: String] {
        var info: [String: String] = [:]
        try db.query("SELECT info FROM files WHERE id = ?", [.int(id)]) { row in
            if let json = row.text(0)?.data(using: .utf8) {
                info = (try? JSONSerialization.jsonObject(with: json) as? [String: String]) ?? [:]
            }
        }
        return info
    }

    /// The last page or chunk stored for a file (where a long file's reading got to, when its info doesn't say).
    func lastPlace(of id: Int64) throws -> Int? {
        var last: Int?
        try db.query("SELECT MAX(loc) FROM segments WHERE file = ? AND kind IN ('page', 'page_image', 'chunk')",
                     [.int(id)]) { last = $0.isNull(0) ? nil : Int($0.double(0)) }
        return last
    }

    /// Settles a file: its state, why (for skipped and failed files, or how far a long one got), and what was learned.
    func finish(_ id: Int64, state: String, detail: String? = nil, info: [String: String] = [:]) throws {
        let json = info.isEmpty ? nil : (try? JSONSerialization.data(withJSONObject: info, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) }
        try db.run("UPDATE files SET state = ?, detail = ?, info = ?, indexed_at = ? WHERE id = ?",
                   [.text(state), .optional(detail), .optional(json), .double(Date().timeIntervalSince1970), .int(id)])
    }
}
