import AppKit
import Observation

/// DDock's app-wide set-aside flags. Original pins, Shelf ordering, bookmarks, and files stay
/// in their owning stores, so releasing a flag restores the same placement without a file move.
@MainActor @Observable
final class QuarantineStore {
    static let shared: QuarantineStore = {
        let environment = ProcessInfo.processInfo.environment
        let preview = environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
        return QuarantineStore(defaults: preview ? nil : .standard)
    }()

    struct Record: Codable, Identifiable {
        let id: String
        let url: URL
        let name: String
        let stampedAt: Date
    }

    private(set) var records: [Record] = []
    private(set) var error: String?
    private(set) var unreadable = false
    private let defaults: UserDefaults?
    private let key = "quarantine.records.v1"

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        guard let data = defaults?.data(forKey: key) else { return }
        do { records = try JSONDecoder().decode([Record].self, from: data) }
        catch {
            unreadable = true
            self.error = String(localized: .quarantineStorageError)
        }
    }

    /// Identity follows saved app/Shelf IDs; URL matching also blocks alternate DDock routes.
    func contains(_ id: String, url: URL) -> Bool {
        records.contains { $0.id == id || $0.url.standardizedFileURL == url.standardizedFileURL }
    }

    func blocks(_ url: URL) -> Bool {
        // Fail closed if flags cannot be decoded. Never overwrite the unreadable document.
        unreadable || records.contains { $0.url.standardizedFileURL == url.standardizedFileURL }
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
