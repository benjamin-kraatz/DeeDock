import Foundation
import Observation

/// Local bookmarks for Launcher copy destinations, independent of display profiles.
@MainActor @Observable
final class LauncherFileDestinationsStore {
    private(set) var destinations: [LauncherFileDestination] = []
    private(set) var requiresReset = false
    private(set) var error: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let bookmark: (URL) throws -> Data
    private static let key = "launcher.file-destinations.v1"

    init(defaults: UserDefaults = .standard,
         bookmark: @escaping (URL) throws -> Data = {
             try $0.bookmarkData(options: [.withSecurityScope],
                                 includingResourceValuesForKeys: nil, relativeTo: nil)
         }) {
        self.defaults = defaults
        self.bookmark = bookmark
    }

    func start() {
        guard let data = defaults.data(forKey: Self.key) else { return }
        do {
            let document = try JSONDecoder().decode(LauncherFileDestinationsDocument.self, from: data)
            guard document.isValid else { throw CocoaError(.coderReadCorrupt) }
            destinations = document.destinations
            requiresReset = false
            error = nil
        } catch {
            // Leave the stored bytes so a later version or manual recovery can still read them.
            destinations = []
            requiresReset = true
            self.error = String(localized: .launcherFileDestinationsStorageFailed)
        }
    }

    func reset() {
        requiresReset = false
        save([])
    }

    /// Adds a folder the user just chose. An existing bookmark for the same location is reused.
    @discardableResult
    func add(_ url: URL) -> LauncherFileDestination? {
        guard !requiresReset else { return nil }
        let standardized = url.standardizedFileURL
        if let existing = destinations.first(where: { $0.url.standardizedFileURL == standardized }) {
            return existing
        }
        guard destinations.count < LauncherFileDestinationsDocument.capacity else {
            error = String(localized: .launcherFileDestinationsLimit)
            return nil
        }
        do {
            let destination = LauncherFileDestination(
                name: FileManager.default.displayName(atPath: standardized.path),
                url: standardized,
                bookmarkData: try bookmark(standardized)
            )
            save(destinations + [destination])
            return destination
        } catch {
            self.error = String(localized: .launcherFileDestinationBookmarkFailed)
            return nil
        }
    }

    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requiresReset, !trimmed.isEmpty,
              let index = destinations.firstIndex(where: { $0.id == id }) else { return }
        var next = destinations
        next[index].name = trimmed
        save(next)
    }

    /// Drops the bookmark. The folder and its files stay on disk.
    func remove(_ id: UUID) {
        guard !requiresReset else { return }
        save(destinations.filter { $0.id != id })
    }

    func repair(_ id: UUID, url: URL) {
        guard !requiresReset, let index = destinations.firstIndex(where: { $0.id == id }) else { return }
        do {
            var next = destinations
            next[index].url = url.standardizedFileURL
            next[index].bookmarkData = try bookmark(url.standardizedFileURL)
            if next[index].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                next[index].name = FileManager.default.displayName(atPath: url.path)
            }
            save(next)
        } catch {
            self.error = String(localized: .launcherFileDestinationBookmarkFailed)
        }
    }

    func resolve(_ id: UUID) -> LauncherFileDestinationAccess? {
        guard let destination = destinations.first(where: { $0.id == id }) else { return nil }
        let access = LauncherFileDestinationAccess(destination)
        guard access.isAvailable else { return nil }
        if access.bookmarkIsStale, let refreshed = try? bookmark(access.url),
           let index = destinations.firstIndex(where: { $0.id == id }) {
            var next = destinations
            next[index].bookmarkData = refreshed
            next[index].url = access.url
            try? persist(next)
        }
        return access
    }

    func isAvailable(_ destination: LauncherFileDestination) -> Bool {
        LauncherFileDestinationAccess(destination, startAccess: { _ in false }, stopAccess: { _ in }).isAvailable
    }

    private func save(_ next: [LauncherFileDestination]) {
        do {
            try persist(next)
            destinations = next
            error = nil
        } catch {
            self.error = String(localized: .launcherFileDestinationsStorageFailed)
        }
    }

    private func persist(_ next: [LauncherFileDestination]) throws {
        let data = try JSONEncoder().encode(LauncherFileDestinationsDocument(destinations: next))
        defaults.set(data, forKey: Self.key)
    }
}
