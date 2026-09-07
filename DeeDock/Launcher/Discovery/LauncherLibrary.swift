import AppKit
import Observation

/// Shared installed-app snapshot, refreshed on deliberate launcher opens, not on pointer movement.
@MainActor @Observable
final class LauncherLibrary {
    private(set) var applications: [LauncherApplication] = []
    private(set) var isLoading = false
    private(set) var skippedDirectories = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var owners: Set<UUID> = []
    @ObservationIgnored private var query: NSMetadataQuery?
    @ObservationIgnored private var queryGeneration = UUID()
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var extraURLs: [URL] = []

    init(applications: [LauncherApplication] = []) { self.applications = applications }

    /// Spotlight supplements directory discovery with user-installed apps at other indexed locations.
    func acquire(_ owner: UUID, extraURLs: [URL]) {
        owners.insert(owner)
        self.extraURLs = extraURLs
        refresh()
        guard query == nil else { return }
        let queryToken = UUID(); queryGeneration = queryToken
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemContentType == %@", "com.apple.application-bundle")
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.queryGeneration == queryToken,
                      let query = self.query, !self.owners.isEmpty else { return }
                query.disableUpdates()
                let urls = query.results.compactMap { ($0 as? NSMetadataItem)?.value(forAttribute: NSMetadataItemPathKey) as? String }.map { URL(fileURLWithPath: $0) }
                query.stop()
                self.extraURLs = extraURLs + urls.filter { LauncherDiscovery.isUserFacingLocation($0) }
                self.refresh()
            }
        }
        self.query = query
        query.start()
    }

    func refresh() {
        task?.cancel()
        let token = UUID(); generation = token
        let urls = extraURLs
        isLoading = true
        task = Task { [weak self] in
            do {
                let snapshot = try await LauncherDiscovery.scan(extraURLs: urls)
                guard !Task.isCancelled, let self, generation == token else { return }
                applications = snapshot.applications
                skippedDirectories = snapshot.skippedDirectories
                isLoading = false
                task = nil
            } catch {
                guard !Task.isCancelled, let self, generation == token else { return }
                isLoading = false
                skippedDirectories = 1
                task = nil
            }
        }
    }

    func release(_ owner: UUID) {
        owners.remove(owner)
        if owners.isEmpty { stop() }
    }

    func stop() {
        queryGeneration = UUID()
        generation = UUID(); task?.cancel(); task = nil; isLoading = false
        query?.stop(); query = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil; owners.removeAll()
    }
}
