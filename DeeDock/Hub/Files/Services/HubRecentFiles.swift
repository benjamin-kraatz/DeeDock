import Foundation
import Observation

/// Recently used files, like Finder's Recents: documents with a Spotlight last-used date in the
/// past 30 days, newest first, at most 60. Folders and apps are left out.
///
/// The query stays live while started, so a file opened elsewhere moves to the top. Updates are
/// coalesced (250 ms) and converted off the main actor; a generation token drops conversions
/// that finish after `stop()` or a newer update.
@MainActor @Observable
final class HubRecentFiles {
    /// Newest first.
    private(set) var items: [HubFileItem] = []

    static let limit = 60
    static let window: TimeInterval = 30 * 24 * 60 * 60

    @ObservationIgnored private var query: NSMetadataQuery?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var refresh: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    nonisolated init() {}

    /// Starts the live query. Calling it while running does nothing.
    func start() {
        guard query == nil else { return }
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(
            format: "kMDItemLastUsedDate >= %@ AND kMDItemContentType != %@ AND kMDItemContentType != %@",
            Date(timeIntervalSinceNow: -Self.window) as NSDate, "public.folder", "com.apple.application-bundle")
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        query.sortDescriptors = [NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)]
        query.notificationBatchingInterval = 0.25
        let center = NotificationCenter.default
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(center.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.queryChanged() }
            })
        }
        self.query = query
        query.start()
    }

    /// Stops the query and keeps the last items.
    func stop() {
        generation = UUID()
        refresh?.cancel()
        refresh = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        query?.stop()
        query = nil
    }

    private func queryChanged() {
        guard let query else { return }
        // Read more than the limit: some hits are hidden or gone and get dropped.
        let hits = HubMetadataResults.hits(from: query, limit: Self.limit + 20)
        let token = UUID()
        generation = token
        refresh?.cancel()
        refresh = Task { [weak self] in
            let found = await HubMetadataResults.items(for: hits)
            guard let self, self.generation == token, !Task.isCancelled else { return }
            self.items = Array(found
                .sorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
                .prefix(Self.limit)
                .map(\.item))
        }
    }

    isolated deinit { stop() }
}
