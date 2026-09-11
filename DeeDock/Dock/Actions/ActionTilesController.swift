import AppKit
import Observation

/// Owns pins, discovery, and single-flight shortcut executions shared by every display.
@MainActor @Observable
final class ActionTilesController {
    private(set) var tiles: [ActionTile] = []
    private(set) var available: [ActionTile] = []
    private(set) var statuses: [UUID: ActionTileStatus] = [:]
    private(set) var loading = false
    /// True after the first discovery attempt finishes, including an empty or failed list.
    private(set) var discovered = false
    private(set) var requiresReset = false
    var error: String?
    @ObservationIgnored var changed: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var discovery: ShortcutProcess?
    @ObservationIgnored private var runs: [UUID: ShortcutProcess] = [:]
    private static let key = "dock.action-tiles.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var dockItems: [ActionDockItem] {
        let availableIDs = Set(available.map(\.id))
        return tiles.map { tile in
            ActionDockItem(
                tile: tile,
                status: statuses[tile.id] ?? .idle,
                wilted: discovered && !availableIDs.contains(tile.id)
            )
        }
    }

    /// Pinned shortcuts as greenhouse plants. Watering calls ``water(_:)``.
    var plants: [ShortcutGreenhousePlant] { dockItems.map(\.plant) }

    func start() {
        guard let data = defaults.data(forKey: Self.key) else { return }
        do {
            let document = try JSONDecoder().decode(ActionTilesDocument.self, from: data)
            guard document.version == 1, document.tiles.count <= 30,
                  Set(document.tiles.map(\.id)).count == document.tiles.count,
                  document.tiles.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw CocoaError(.coderReadCorrupt)
            }
            tiles = document.tiles
        } catch { requiresReset = true; self.error = String(localized: .actionsStorageFailed) }
        changed?()
    }

    /// Starts discovery when Settings, Watch, Launcher file actions, or an enabled greenhouse
    /// first need the list. Skips canvas and playground hosts.
    func ensureLoaded() {
        guard !loading, !discovered else { return }
        let environment = ProcessInfo.processInfo.environment
        if environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1" {
            return
        }
        refresh()
    }

    /// Lists installed shortcuts without running them. Reload and first appearance both use this.
    func refresh() {
        guard !loading else { return }
        loading = true; error = nil
        let job = ShortcutProcess()
        discovery = job
        job.start(arguments: ["list", "--show-identifiers"], capturesOutput: true, deadline: .seconds(20)) { [weak self] result in
            guard let self else { return }
            discovery = nil; loading = false; discovered = true
            do {
                let output = try result.get()
                available = try output.split(separator: "\n").map { line in
                    guard line.hasSuffix(")"), let split = line.range(of: " (", options: .backwards),
                          let id = UUID(uuidString: String(line[split.upperBound...].dropLast())) else {
                        throw CocoaError(.coderReadCorrupt)
                    }
                    return ActionTile(id: id, name: String(line[..<split.lowerBound]))
                }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            } catch { self.error = String(localized: .actionsDiscoveryFailed(error.localizedDescription)) }
            changed?()
        }
    }

    func pin(_ tile: ActionTile) {
        guard !requiresReset, tiles.count < 30, !tiles.contains(where: { $0.id == tile.id }) else { return }
        save(tiles + [tile])
    }
    func unpin(_ id: UUID) {
        guard !requiresReset, runs[id] == nil else { return }
        save(tiles.filter { $0.id != id })
    }
    func move(_ id: UUID, by distance: Int) {
        guard !requiresReset, let index = tiles.firstIndex(where: { $0.id == id }) else { return }
        let target = index + distance
        guard tiles.indices.contains(target) else { return }
        var next = tiles; next.swapAt(index, target); save(next)
    }
    func reset() { requiresReset = false; save([]) }
    func setAcceptsFiles(_ id: UUID, _ value: Bool) {
        guard !requiresReset, let index = tiles.firstIndex(where: { $0.id == id }) else { return }
        var next = tiles
        next[index].acceptsFiles = value
        save(next)
    }

    private func save(_ next: [ActionTile]) {
        do {
            let data = try JSONEncoder().encode(ActionTilesDocument(tiles: next))
            defaults.set(data, forKey: Self.key)
            tiles = next; error = nil; changed?()
        } catch { self.error = String(localized: .actionsStorageFailed) }
    }

    /// Runs only after a click, keyboard action, or accepted drop. No uncertain run is retried.
    @discardableResult
    func run(_ id: UUID, files: DocumentResourceAccess? = nil, finished: (() -> Void)? = nil) -> Bool {
        tiles.contains(where: { $0.id == id }) && start(id, files: files) { _ in finished?() }
    }

    /// Waters a plant by running the pinned shortcut through the existing Action Tiles runner.
    @discardableResult
    func water(_ id: UUID) -> Bool { run(id) }

    /// One explicit run of a configured Shortcut ID. The Shortcut need not be pinned.
    /// A second overlapping run of the same identifier is rejected and never retried.
    func runConfigured(_ id: UUID) async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            guard start(id, completion: { result in
                continuation.resume(returning: result.map { _ in () })
            }) else {
                continuation.resume(returning: .failure(CocoaError(.coderInvalidValue)))
                return
            }
        }
    }

    func knownShortcutName(for id: UUID) -> String? {
        tiles.first { $0.id == id }?.name ?? available.first { $0.id == id }?.name
    }

    func knowsShortcut(_ id: UUID) -> Bool {
        tiles.contains { $0.id == id } || available.contains { $0.id == id }
    }

    @discardableResult
    private func start(_ id: UUID, files: DocumentResourceAccess? = nil,
                       completion: @escaping (Result<String, Error>) -> Void) -> Bool {
        guard runs[id] == nil else { return false }
        let job = ShortcutProcess()
        runs[id] = job
        if tiles.contains(where: { $0.id == id }) { statuses[id] = .running }
        changed?()
        var arguments = ["run", id.uuidString]
        if let files, !files.urls.isEmpty { arguments += ["--input-path"] + files.urls.map(\.path) }
        job.start(arguments: arguments) { [weak self] result in
            // File access outlives the helper's completion, including errors and cancellation.
            defer { withExtendedLifetime(files) {} }
            guard let self else {
                completion(result)
                return
            }
            runs[id] = nil
            switch result {
            case .success:
                if tiles.contains(where: { $0.id == id }) { statuses[id] = .succeeded }
            case .failure(let error):
                let message = error is CancellationError ? String(localized: .actionsCancelled) : error.localizedDescription
                if tiles.contains(where: { $0.id == id }) { statuses[id] = .failed(message) }
                self.error = message
            }
            changed?()
            completion(result)
        }
        return true
    }
    func cancel(_ id: UUID) { runs[id]?.cancel() }
    func stop() {
        discovery?.cancel(); discovery = nil
        let pending = Array(runs.values)
        pending.forEach { $0.cancel() }
        runs = [:]; changed = nil
    }
}
