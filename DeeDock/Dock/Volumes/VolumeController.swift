import AppKit
import Observation
import UniformTypeIdentifiers

/// Owns the shared snapshot of mounted volumes and every eject DOKK starts.
///
/// Mount changes come from NSWorkspace notifications; nothing polls. Free space is re-read when a
/// volume card opens, which is the only place it is shown. Local volumes publish before any
/// network share is read, and each share is read on its own, so a slow file server holds back
/// only its own tile.
@MainActor @Observable
final class VolumeController {
    /// Every mounted volume in arrangement order, hidden ones included. Settings lists these.
    private(set) var items: [VolumeDockItem] = []
    /// Order and visibility the user chose. Edits republish `items`.
    let arrangement: VolumeArrangementStore
    /// Called after `items` changes, so every dock can rebuild its entries.
    @ObservationIgnored var didChange: (() -> Void)?
    /// Called before a volume unmounts, from DOKK or from Finder, so DOKK can release open
    /// directory handles (a folder stack's watcher) that would otherwise block the unmount.
    @ObservationIgnored var volumeWillUnmount: ((URL) -> Void)?

    @ObservationIgnored private var infos: [VolumeInfo] = []
    /// Dock-candidate mounts from the latest scan, in mount order.
    @ObservationIgnored private var mounts: [MountedVolume] = []
    /// Share reads in flight, by mount URL. A rescan never starts a second read of the same
    /// share, so a wedged server ties up one thread however many mount notifications arrive.
    @ObservationIgnored private var shareReads: [URL: Task<Void, Never>] = [:]
    @ObservationIgnored private var icons: [String: NSImage] = [:]
    @ObservationIgnored private var ejecting: Set<String> = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    /// Volume IDs mounted when the arrangement last recorded them, so arrivals and departures
    /// can be told apart.
    @ObservationIgnored private var remembered: Set<String> = []

    /// Uses the standard-defaults arrangement unless one is supplied.
    init(arrangement: VolumeArrangementStore? = nil) {
        self.arrangement = arrangement ?? VolumeArrangementStore()
        self.arrangement.didChange = { [weak self] in self?.publish() }
    }

    /// The volumes docks show: mounted, in arrangement order, without hidden drives.
    var dockItems: [VolumeDockItem] { items.filter { !arrangement.isHidden($0.volumeID) } }

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
                     NSWorkspace.didRenameVolumeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rescan() }
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.willUnmountNotification, object: nil,
                                             queue: .main) { [weak self] note in
            let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
            MainActor.assumeIsolated {
                guard let self, let url else { return }
                self.volumeWillUnmount?(url)
            }
        })
        rescan()
    }

    func stop() {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        generation = UUID()
        scanTask?.cancel(); scanTask = nil
        shareReads.values.forEach { $0.cancel() }
        shareReads = [:]
        didChange = nil; volumeWillUnmount = nil
    }

    func item(_ volumeID: String) -> VolumeDockItem? { items.first { $0.volumeID == volumeID } }

    /// Re-reads one volume's capacity for an opening card. Returns nil once the volume is gone.
    func refreshCapacity(_ volumeID: String) async -> VolumeDockItem? {
        guard let url = item(volumeID)?.url else { return nil }
        let token = generation
        let fresh = await VolumeReads.run(qos: .userInitiated) { VolumeScanner.info(for: url) }
        guard generation == token, let fresh, fresh.volumeID == volumeID,
              let index = infos.firstIndex(where: { $0.volumeID == volumeID }) else {
            return item(volumeID)
        }
        if infos[index] != fresh {
            infos[index] = fresh
            publish()
        }
        return item(volumeID)
    }

    /// Ejects the volume, dimming its tile meanwhile. On success the tile leaves at once, before
    /// the unmount notification arrives, so the dock never shows a dead volume.
    func eject(_ volumeID: String, force: Bool) async -> VolumeEjectResult {
        guard let url = item(volumeID)?.url, !ejecting.contains(volumeID) else {
            return .failed(String(localized: .volumeUnavailable))
        }
        volumeWillUnmount?(url)
        ejecting.insert(volumeID)
        publish()
        let result = force ? await VolumeEjector.forceEject(url) : await VolumeEjector.eject(url)
        ejecting.remove(volumeID)
        if result == .ejected {
            infos.removeAll { $0.volumeID == volumeID }
            // Keeps a share read still in flight from bringing the tile back.
            mounts.removeAll { $0.url == url }
            // Replaces any scan that began before the unmount and would bring the tile back, and
            // drops sibling partitions that `.allPartitionsAndEjectDisk` unmounted with it.
            rescan()
        }
        publish()
        return result
    }

    /// Re-reads mounted volumes in two steps. Local volumes are read and published first, and
    /// nothing touches a share before that publish. Each share is then read on its own.
    ///
    /// Until its read returns, a share keeps the info from its previous read, so mounting a USB
    /// stick does not blank every share tile. A share that is no longer mounted leaves with the
    /// first publish.
    private func rescan() {
        scanTask?.cancel()
        let token = generation
        scanTask = Task { [weak self] in
            // The kernel's cached mount table tells local volumes from shares without asking a server.
            let mounts = await VolumeReads.run { VolumeScanner.mounts() }
            let local = await VolumeReads.run { VolumeScanner.scan(mounts.filter(\.isLocal)) }
            guard let self, !Task.isCancelled, generation == token else { return }
            let missing = local.filter { self.icons[$0.volumeID] == nil }
            if !missing.isEmpty {
                let loaded = await VolumeReads.run { VolumeIcons.load(missing) }
                guard !Task.isCancelled, generation == token else { return }
                for (id, icon) in loaded { icons[id] = icon.image }
            }
            scanTask = nil
            self.mounts = mounts
            let shares = mounts.filter { !$0.isLocal }.map(\.url)
            commit(local + infos.filter { shares.contains($0.url) })
            for share in shares { readShare(share) }
        }
    }

    /// Reads one share and updates its tile, unless a read of it is already in flight.
    private func readShare(_ url: URL) {
        guard shareReads[url] == nil else { return }
        let token = generation
        shareReads[url] = Task { [weak self] in
            let info = await VolumeReads.run { VolumeScanner.info(for: url) }
            guard let self, generation == token else { return }
            if let info, icons[info.volumeID] == nil {
                let loaded = await VolumeReads.run { VolumeIcons.load([info]) }
                guard generation == token else { return }
                for (id, icon) in loaded { icons[id] = icon.image }
            }
            shareReads[url] = nil
            // A share that unmounted during its read already left with a later scan's publish.
            guard mounts.contains(where: { $0.url == url && !$0.isLocal }) else { return }
            commit(infos.filter { $0.url != url } + (info.map { [$0] } ?? []))
        }
    }

    /// Stores `volumes` in mount order and publishes when anything changed.
    private func commit(_ volumes: [VolumeInfo]) {
        let ordered = VolumeScanner.ordered(volumes, by: mounts)
        guard ordered != infos else { return }
        infos = ordered
        publish()
    }

    private func publish() {
        let ids = Set(infos.map(\.volumeID))
        icons = icons.filter { ids.contains($0.key) }
        ejecting.formIntersection(ids)
        // Saves only on an arrival, departure, or rename, so capacity refreshes write nothing.
        arrangement.remember(infos, previouslyMounted: remembered)
        remembered = ids
        items = arrangement.arrangement.arranged(infos, id: \.volumeID).map { info in
            VolumeDockItem(info: info, icon: icon(for: info), isEjecting: ejecting.contains(info.volumeID))
        }
        didChange?()
    }

    /// Cached so each dock rebuild hands SwiftUI the same image instead of new artwork. Scans
    /// load real icons before publishing; the generic volume icon is only a fallback.
    private func icon(for info: VolumeInfo) -> NSImage {
        if let icon = icons[info.volumeID] { return icon }
        let icon = NSWorkspace.shared.icon(for: .volume)
        icon.size = NSSize(width: 128, height: 128)
        return icon
    }
}

/// Reads Finder's icon for each volume, including custom volume icons. That reads the volume,
/// which can stall on a slow network share, so it runs off the main actor.
nonisolated enum VolumeIcons {
    /// `NSImage` is not `Sendable`; each image is created here and handed over once, never shared.
    struct Loaded: @unchecked Sendable {
        let image: NSImage
    }

    static func load(_ volumes: [VolumeInfo]) -> [(String, Loaded)] {
        volumes.map { info in
            let icon = NSWorkspace.shared.icon(forFile: info.url.path)
            icon.size = NSSize(width: 128, height: 128)
            return (info.volumeID, Loaded(image: icon))
        }
    }
}
