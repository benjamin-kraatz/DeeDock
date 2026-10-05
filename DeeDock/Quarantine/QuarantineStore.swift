import AppKit
import Observation

/// DDock's app-wide set-aside flags. Original pins, Shelf ordering, bookmarks, and files stay
/// in their owning stores, so releasing a flag restores the same placement without a file move.
@MainActor @Observable
final class QuarantineStore {
    static let shared = QuarantineStore(
        defaults: HostEnvironment.isPreview || HostEnvironment.isTestHost ? nil : .standard)

    struct Record: Codable, Identifiable {
        let id: String
        let url: URL
        let name: String
        let stampedAt: Date
    }

    private(set) var records: [Record] = [] {
        didSet { indexRecords() }
    }
    // Dock buttons check membership during layout. An empty `records` returns before any
    // file-system work. An exact standardized path hits `recordURLs`; a miss resolves symlinks.
    @ObservationIgnored private var recordIDs: Set<String> = []
    @ObservationIgnored private var recordURLs: Set<URL> = []
    private(set) var error: String?
    private(set) var unreadable = false
    private let defaults: UserDefaults?
    private let key = "quarantine.records.v1"

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        guard let data = defaults?.data(forKey: key) else { return }
        do { records = try JSONDecoder().decode([Record].self, from: data); indexRecords() }
        catch {
            unreadable = true
            self.error = String(localized: .quarantineStorageError)
        }
    }

    /// Identity follows saved app and Shelf IDs. A saved URL also matches that file, a symlink
    /// to it, and anything inside it, so another DDock route to the same target stays blocked.
    func contains(_ id: String, url: URL) -> Bool {
        // Reading `records` keeps SwiftUI observation on the store's persisted state.
        guard !records.isEmpty else { return false }
        return recordIDs.contains(id) || urlMatches(url)
    }

    /// Whether opening `url` is refused. A saved folder covers that folder, a symlink to it,
    /// and its descendants. Unreadable flag data blocks every URL and is left untouched.
    func blocks(_ url: URL) -> Bool {
        // Fail closed if flags cannot be decoded. Never overwrite the unreadable document.
        if unreadable { return true }
        guard !records.isEmpty else { return false }
        return urlMatches(url)
    }

    /// A saved URL covers that file, a symlink to it, and any descendant.
    ///
    /// Exact `standardizedFileURL` hits return before symlink resolution. `standardizedFileURL`
    /// does not resolve symlinks or fold case, so a miss uses `isSameOrDescendant`, which does both.
    private func urlMatches(_ url: URL) -> Bool {
        let standardized = url.standardizedFileURL
        if recordURLs.contains(standardized) { return true }
        return recordURLs.contains { url.isSameOrDescendant(of: $0, resolvingSymlinks: true) }
    }

    func requireAllowed(_ url: URL, id: String? = nil) throws {
        if blocks(url) || id.map({ value in records.contains { $0.id == value } }) == true {
            throw NSError(domain: "DDock.Quarantine", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: String(localized: .quarantineBlocked)])
        }
    }

    enum Change { case stamped, released }

    /// Returns the persisted transition. Presentation and sound belong to the caller.
    @discardableResult
    func toggle(id: String, url: URL, name: String) -> Change? {
        guard !unreadable else { return nil }
        let existing = records.filter { $0.id == id || $0.url.standardizedFileURL == url.standardizedFileURL }
        var next = records.filter { record in !existing.contains { $0.id == record.id } }
        if existing.isEmpty { next.append(Record(id: id, url: url, name: name, stampedAt: .now)) }
        guard save(next) else { return nil }
        return existing.isEmpty ? .stamped : .released
    }

    @discardableResult
    func release(_ record: Record) -> Bool {
        save(records.filter { $0.id != record.id })
    }

    private func indexRecords() {
        recordIDs = Set(records.map(\.id))
        // Keep the symlink path. Resolving here would freeze a target that can change later;
        // `urlMatches` resolves both sides on each check.
        recordURLs = Set(records.map(\.url.standardizedFileURL))
    }

    private func save(_ next: [Record]) -> Bool {
        guard !unreadable else { return false }
        do {
            let data = try JSONEncoder().encode(next)
            defaults?.set(data, forKey: key)
            records = next
            error = nil
            return true
        } catch {
            self.error = String(localized: .quarantineStorageError)
            return false
        }
    }
}
