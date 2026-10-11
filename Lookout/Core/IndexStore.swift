// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

import Foundation

/// The on-disk index: one SQLite file with files, their segments (with fp16 vectors), and an FTS5 table.
///
/// Vectors live in the same database as everything else, so a crash can never leave them out of step with the
/// rows that describe them. At this scale (~20k vectors, ~30 MB) brute-force search over an in-memory copy is a
/// few milliseconds; no vector database needed.
///
/// The index service is the only writer (`init(directory:)`). The app opens it read-only (`openReadOnly`), which
/// WAL lets it do while the service writes. One instance is used from one thread at a time.
nonisolated final class IndexStore {
    let directory: URL
    let db: Database
    let file: URL

    /// Lookout's first schema. DigUp's migrations (its schemas 1–5) aren't carried over: no Lookout index predates
    /// this one, and the layout is DigUp's schema 5 plus `files.last_used`, without the code index.
    static let schemaVersion: Int64 = 1

    /// The index's file in the index folder.
    static let mainFile = "index.sqlite"

    /// Keyword search's tokenizer. Marks (M*) count as letters, so Bengali vowel signs and Arabic harakat stay inside
    /// their words: by default SQLite splits on them ("কলকাতায়" became "কলক", "ত", "য").
    static let tokenizer = "porter unicode61 remove_diacritics 2 categories 'L* N* Co M*'"
    /// Keyword search's table: words are matched in `body`, normalized (`SearchText`); `original` keeps the text as it's
    /// written when normalizing changed it (Arabic with hamza or harakat, Bengali with joiners), for showing it.
    static let ftsColumns = "name, body, original UNINDEXED, tokenize = \"\(tokenizer)\""

    /// When set, `pending`, `pendingCount`, `unfinished` and `counts` see only files under these folders: the service
    /// sets the folders that are there and readable right now, so files on an unplugged drive neither fail nor count
    /// as waiting.
    var scope: [String]? {
        didSet {
            guard let scope else { (scopeSQL, scopeValues) = ("", []); return }
            scopeSQL = scope.isEmpty ? " AND 0"
                : " AND (" + scope.map { _ in "(path >= ? AND path < ?)" }.joined(separator: " OR ") + ")"
            scopeValues = scope.flatMap { root -> [SQLValue] in
                let prefix = root.hasSuffix("/") ? root : root + "/"
                return [.text(prefix), .text(prefix + "\u{10FFFF}")]
            }
        }
    }
    /// `scope` as a WHERE clause continuation and its values.
    private(set) var scopeSQL = ""
    private(set) var scopeValues: [SQLValue] = []

    /// Opens the index in `directory` for writing, creating the folder and the schema when they aren't there.
    ///
    /// - Throws: The folder can't be created, SQLite can't open the file, or a newer schema made it.
    init(directory: URL, file name: String = IndexStore.mainFile) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.directory = directory
        file = directory.appendingPathComponent(name)
        db = try Database(path: file.path)
        try createIfNeeded()
    }

    private init(readOnly file: URL) throws {
        directory = file.deletingLastPathComponent()
        self.file = file
        db = try Database(path: file.path, readOnly: true)
    }

    /// Opens the index for reading only: no folder or schema is created, and writes fail. Nil while there's nothing
    /// to read yet: no file, or a file whose schema the service hasn't committed.
    ///
    /// - Throws: SQLite can't open an existing file, or a newer schema made it.
    static func openReadOnly(directory: URL, file name: String = IndexStore.mainFile) throws -> IndexStore? {
        let file = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let store = try IndexStore(readOnly: file)
        let version = try store.userVersion()
        guard version <= schemaVersion else {
            throw Database.Failure(message: "this index was made by a newer DOKK (schema \(version))")
        }
        return version == 0 ? nil : store
    }

    /// Bytes on disk: the database and its write-ahead log.
    static func size(of file: URL) -> Int64 {
        [file.path, file.path + "-wal"].reduce(0) { total, path in
            total + ((try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0)
        }
    }

    private func userVersion() throws -> Int64 {
        var version: Int64 = 0
        try db.query("PRAGMA user_version") { version = $0.int(0) }
        return version
    }

    private func createIfNeeded() throws {
        var version = try userVersion()
        guard version <= Self.schemaVersion else {
            throw Database.Failure(message: "this index was made by a newer DOKK (schema \(version))")
        }
        guard version < Self.schemaVersion else { return }
        // Two writers opening a new index at once (the service and the bench on one folder): one creates it while
        // the other waits (up to a minute, not the usual 5 s), then sees it done.
        try db.execute("PRAGMA busy_timeout = 60000")
        defer { try? db.execute("PRAGMA busy_timeout = 5000") }
        try db.transaction {
            version = try userVersion()
            if version == 0 { try create() }
        }
    }

    private func create() throws {
        try db.execute("""
            CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE files(
                id INTEGER PRIMARY KEY,
                path TEXT NOT NULL UNIQUE,
                kind TEXT NOT NULL,
                size INTEGER NOT NULL,
                mtime REAL NOT NULL,
                inode INTEGER NOT NULL,
                device INTEGER NOT NULL,
                last_used REAL,                           -- Spotlight's kMDItemLastUsedDate, when it has one
                state TEXT NOT NULL DEFAULT 'pending',   -- pending | done | partial | skipped | failed
                detail TEXT,                              -- why skipped/failed, or how far a long file has been read
                info TEXT,                                -- JSON: pixels, pages, date taken; read_to/read_end
                indexed_at REAL
            );
            CREATE INDEX files_inode ON files(device, inode);
            CREATE INDEX files_state ON files(state, kind);
            CREATE TABLE segments(
                id INTEGER PRIMARY KEY,
                file INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
                kind TEXT NOT NULL,       -- SegmentKind
                modality TEXT NOT NULL,   -- Modality of the vector ('none' when there is no vector)
                loc REAL,                 -- PDF page number, or chunk number
                loc_end REAL,
                excerpt TEXT,
                vec BLOB                  -- 768 × float16, L2-normalized
            );
            CREATE INDEX segments_file ON segments(file);
            CREATE VIRTUAL TABLE fts USING fts5(\(Self.ftsColumns));
            PRAGMA user_version = \(Self.schemaVersion);
            """)
    }

    // MARK: Meta

    /// A value from `meta`: `fingerprint` (the vector source and the settings the vectors were made with) and
    /// `vector_source` (the model alone, which the query encoder must match).
    func meta(_ key: String) throws -> String? {
        var value: String?
        try db.query("SELECT value FROM meta WHERE key = ?", [.text(key)]) { value = $0.text(0) }
        return value
    }

    /// Sets a `meta` value, or removes it when `value` is nil.
    func setMeta(_ key: String, _ value: String?) throws {
        if let value {
            try db.run("INSERT INTO meta(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                       [.text(key), .text(value)])
        } else {
            try db.run("DELETE FROM meta WHERE key = ?", [.text(key)])
        }
    }
}
