import Foundation
import UniformTypeIdentifiers

/// Files and folders you open, from Spotlight's `kMDItemLastUsedDate`, as a live query.
///
/// Unlike the Hub's Recents, folders are included (Finder updates their last-used date too). Apps
/// are left out: `FlixAppActivitySource` reports them from NSWorkspace, which is exact. Every value
/// comes from Spotlight's own attributes, so this never touches a file on disk and can never make
/// macOS ask for folder access.
///
/// The first gather seeds the history with the newest ``seedLimit`` results; later updates report
/// only what Spotlight says changed. Each gather or update is delivered as one batch, which the
/// history merges in a single pass (`FlixHistoryDocument.record(batch:)`), so a busy query never
/// rescans the whole history per result. Reading a result touches only the query's in-memory
/// attributes, never the file system, so it stays on the main actor where the query delivers.
/// Rows recorded from Spotlight carry no file identity; the coordinator's background pass reads it
/// off the main actor. Notification observers and the query are removed by ``stop()``.
@MainActor
final class FlixSpotlightSource {
    /// How far back the query looks.
    static let window: TimeInterval = 30 * 86_400
    /// Results read from the first gather.
    static let seedLimit = 300

    /// Receives each batch of events on the main actor.
    var deliver: (([FlixActivityEvent]) -> Void)?

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var includesFolders = true

    var isRunning: Bool { query != nil }

    /// Starts the query; restarting with a different folder choice rebuilds it.
    func start(includingFolders: Bool) {
        if query != nil, includesFolders == includingFolders { return }
        stop()
        includesFolders = includingFolders
        let query = NSMetadataQuery()
        var format = "kMDItemLastUsedDate >= %@ AND kMDItemContentType != %@"
        var arguments: [Any] = [Date(timeIntervalSinceNow: -Self.window) as NSDate, "com.apple.application-bundle"]
        if !includingFolders {
            format += " AND kMDItemContentType != %@"
            arguments.append("public.folder")
        }
        query.predicate = NSPredicate(format: format, argumentArray: arguments)
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        query.sortDescriptors = [NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)]
        query.notificationBatchingInterval = 1
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.gathered() }
        })
        observers.append(center.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main) {
            [weak self] note in
            let changed = (note.userInfo?[NSMetadataQueryUpdateChangedItemsKey] as? [NSMetadataItem] ?? [])
                + (note.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem] ?? [])
            MainActor.assumeIsolated { self?.updated(changed) }
        })
        self.query = query
        query.start()
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        query?.stop()
        query = nil
    }

    private func gathered() {
        guard let query else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }
        let count = min(query.resultCount, Self.seedLimit)
        let events = (0..<count).compactMap { query.result(at: $0) as? NSMetadataItem }.compactMap(Self.event)
        deliver?(events)
    }

    private func updated(_ items: [NSMetadataItem]) {
        let events = items.compactMap(Self.event)
        guard !events.isEmpty else { return }
        deliver?(events)
    }

    /// One Spotlight result as an "opened" event, or nil for hidden items and results without a date.
    static func event(from item: NSMetadataItem) -> FlixActivityEvent? {
        guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
              let lastUsed = item.value(forAttribute: "kMDItemLastUsedDate") as? Date,
              !path.split(separator: "/").contains(where: { $0.hasPrefix(".") }) else { return nil }
        let typeIdentifier = item.value(forAttribute: NSMetadataItemContentTypeKey) as? String
        let type = typeIdentifier.flatMap(UTType.init)
        let isFolder = typeIdentifier == "public.folder" || type?.conforms(to: .folder) == true
        let isScreenshot = (item.value(forAttribute: "kMDItemIsScreenCapture") as? NSNumber)?.boolValue ?? false
        let name = item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String
            ?? (path as NSString).lastPathComponent
        let whereFroms = item.value(forAttribute: NSMetadataItemWhereFromsKey) as? [String] ?? []
        let source = FlixPaths.sourcePageAndIdentity(fromWhereFroms: whereFroms)
        return FlixActivityEvent(path: path, name: name,
                                 kind: FlixItemKind.classify(contentType: type, isDirectory: isFolder,
                                                             isPackage: type?.conforms(to: .package) == true,
                                                             isScreenshot: isScreenshot),
                                 activity: .opened, date: lastUsed,
                                 sourcePage: source?.page, sourcePageIdentity: source?.identity,
                                 contentTypeIdentifier: typeIdentifier,
                                 byteSize: (item.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber)?.int64Value)
    }

    isolated deinit { stop() }
}
