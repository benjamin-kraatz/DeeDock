// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

import Foundation
import SQLite3

/// A thin wrapper over the system SQLite (FTS5 built in). One connection, used from one thread at a time.
///
/// A writable connection turns on WAL, so the app's read-only connection can read while the index service writes.
nonisolated final class Database {
    /// An SQLite error, with the statement it came from.
    struct Failure: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    let handle: OpaquePointer
    let isReadOnly: Bool

    /// Opens (or, unless `readOnly`, creates) the database at `path`.
    ///
    /// A read-only connection never writes: it doesn't set the journal mode (WAL is a property of the file, set by
    /// the writer) and refuses writes with `query_only`.
    ///
    /// - Throws: `Failure` when SQLite can't open the file (a read-only open of a file that isn't there, too).
    init(path: String, readOnly: Bool = false) throws {
        var db: OpaquePointer?
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open \(path)"
            sqlite3_close(db)
            throw Failure(message: message)
        }
        handle = db
        isReadOnly = readOnly
        sqlite3_busy_timeout(db, 5000)
        if readOnly {
            try execute("PRAGMA query_only = ON;")
        } else {
            try execute("PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL; PRAGMA foreign_keys = ON;")
        }
    }

    deinit { sqlite3_close_v2(handle) }

    /// Runs one or more statements that return no rows.
    ///
    /// - Throws: `Failure` with SQLite's message and the start of the SQL.
    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? errorMessage
            sqlite3_free(error)
            throw Failure(message: "\(message) (in: \(sql.prefix(120)))")
        }
    }

    /// Runs `sql` with `values` bound and calls `row` for each result row.
    ///
    /// - Throws: `Failure` from SQLite, or whatever `row` throws.
    func query(_ sql: String, _ values: [SQLValue] = [], row: (Statement) throws -> Void = { _ in }) throws {
        let statement = try Statement(self, sql)
        try statement.bind(values)
        while try statement.step() { try row(statement) }
    }

    /// Runs one statement with `values` bound, ignoring any rows.
    func run(_ sql: String, _ values: [SQLValue] = []) throws { try query(sql, values) }

    /// Runs `body` in an immediate transaction: committed when it returns, rolled back when it throws.
    @discardableResult
    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    var lastInsertID: Int64 { sqlite3_last_insert_rowid(handle) }
    var errorMessage: String { String(cString: sqlite3_errmsg(handle)) }

    /// A prepared statement, finalized when it goes away. It keeps its database alive.
    final class Statement {
        private let statement: OpaquePointer
        private let db: Database

        init(_ db: Database, _ sql: String) throws {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db.handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw Failure(message: "\(db.errorMessage) (in: \(sql.prefix(160)))")
            }
            self.statement = statement
            self.db = db
        }

        deinit { sqlite3_finalize(statement) }

        func bind(_ values: [SQLValue]) throws {
            for (offset, value) in values.enumerated() {
                let index = Int32(offset + 1)
                let status: Int32
                switch value {
                case .int(let number): status = sqlite3_bind_int64(statement, index, number)
                case .double(let number): status = sqlite3_bind_double(statement, index, number)
                case .text(let text): status = sqlite3_bind_text(statement, index, text, -1, Database.transient)
                case .blob(let data):
                    status = data.withUnsafeBytes {
                        sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), Database.transient)
                    }
                case .null: status = sqlite3_bind_null(statement, index)
                }
                guard status == SQLITE_OK else { throw Failure(message: db.errorMessage) }
            }
        }

        /// True while there's a row to read.
        func step() throws -> Bool {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: return true
            case SQLITE_DONE: return false
            default: throw Failure(message: db.errorMessage)
            }
        }

        func int(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }
        func double(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }
        func isNull(_ column: Int32) -> Bool { sqlite3_column_type(statement, column) == SQLITE_NULL }

        func text(_ column: Int32) -> String? {
            sqlite3_column_text(statement, column).map { String(cString: $0) }
        }

        func blob(_ column: Int32) -> Data? {
            guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
            return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
        }
    }

    /// SQLITE_TRANSIENT: SQLite copies bound text/blobs, so Swift's temporary buffers are safe to pass.
    fileprivate static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

/// A value bound to a statement's `?`.
nonisolated enum SQLValue {
    case int(Int64), double(Double), text(String), blob(Data), null

    static func optional(_ text: String?) -> SQLValue { text.map { .text($0) } ?? .null }
    static func optional(_ number: Double?) -> SQLValue { number.map { .double($0) } ?? .null }
}
