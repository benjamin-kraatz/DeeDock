import AppKit
import Observation

/// Owns pins, discovery, and single-flight shortcut executions shared by every display.
@MainActor @Observable
final class ActionTilesController {
    private(set) var tiles: [ActionTile] = []
    private(set) var available: [ActionTile] = []
    private(set) var statuses: [UUID: ActionTileStatus] = [:]
    private(set) var loading = false
    private(set) var requiresReset = false
    var error: String?
    @ObservationIgnored var changed: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var discovery: ShortcutProcess?
    @ObservationIgnored private var runs: [UUID: ShortcutProcess] = [:]
    private static let key = "dock.action-tiles.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var dockItems: [ActionDockItem] { tiles.map { ActionDockItem(tile: $0, status: statuses[$0.id] ?? .idle) } }

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

    /// Discovery is explicitly requested from Settings; it never runs a shortcut.
    func refresh() {
        guard !loading else { return }
        loading = true; error = nil
        let job = ShortcutProcess()
        discovery = job
        job.start(arguments: ["list", "--show-identifiers"], capturesOutput: true, deadline: .seconds(20)) { [weak self] result in
            guard let self else { return }
            discovery = nil; loading = false
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

    private func save(_ next: [ActionTile]) {
        do {
            let data = try JSONEncoder().encode(ActionTilesDocument(tiles: next))
            defaults.set(data, forKey: Self.key)
            tiles = next; error = nil; changed?()
        } catch { self.error = String(localized: .actionsStorageFailed) }
    }

    /// Runs only after a click, keyboard action, or accepted drop. No uncertain run is retried.
    @discardableResult
    func run(_ id: UUID, files: DocumentResourceAccess? = nil) -> Bool {
        guard tiles.contains(where: { $0.id == id }), runs[id] == nil else { return false }
        let job = ShortcutProcess()
        runs[id] = job; statuses[id] = .running; changed?()
        var arguments = ["run", id.uuidString]
        if let files, !files.urls.isEmpty { arguments += ["--input-path"] + files.urls.map(\.path) }
        job.start(arguments: arguments) { [weak self] result in
            // File access outlives the helper's completion, including errors and cancellation.
            defer { withExtendedLifetime(files) {} }
            guard let self else { return }
            runs[id] = nil
            switch result {
            case .success: statuses[id] = .succeeded
            case .failure(let error):
                let message = error is CancellationError ? String(localized: .actionsCancelled) : error.localizedDescription
                statuses[id] = .failed(message)
                self.error = message
            }
            changed?()
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
