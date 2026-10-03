import AppKit
import Observation
import UniformTypeIdentifiers

/// Owns the shared snapshot of mounted volumes and every eject DOKK starts.
///
/// Mount changes come from NSWorkspace notifications; nothing polls. Free space is re-read when a
/// volume card opens, which is the only place it is shown.
@MainActor @Observable
final class VolumeController {
    private(set) var items: [VolumeDockItem] = []
    /// Called after `items` changes, so every dock can rebuild its entries.
    @ObservationIgnored var didChange: (() -> Void)?
    /// Called before a volume unmounts, from DOKK or from Finder, so DOKK can release open
    /// directory handles (a folder stack's watcher) that would otherwise block the unmount.
    @ObservationIgnored var volumeWillUnmount: ((URL) -> Void)?

    @ObservationIgnored private var infos: [VolumeInfo] = []
    @ObservationIgnored private var icons: [String: NSImage] = [:]
    @ObservationIgnored private var ejecting: Set<String> = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

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
        didChange = nil; volumeWillUnmount = nil
    }

    func item(_ volumeID: String) -> VolumeDockItem? { items.first { $0.volumeID == volumeID } }

    /// Re-reads one volume's capacity for an opening card. Returns nil once the volume is gone.
    func refreshCapacity(_ volumeID: String) async -> VolumeDockItem? {
        guard let url = item(volumeID)?.url else { return nil }
        let token = generation
        let fresh = await Task.detached(priority: .userInitiated) { VolumeScanner.info(for: url) }.value
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
            // Replaces any scan that began before the unmount and would bring the tile back, and
            // drops sibling partitions that `.allPartitionsAndEjectDisk` unmounted with it.
            rescan()
        }
        publish()
        return result
    }

    private func rescan() {
        scanTask?.cancel()
        let token = generation
        scanTask = Task { [weak self] in
            let scanned = await Task.detached(priority: .utility) { VolumeScanner.scan() }.value
            guard let self, !Task.isCancelled, generation == token else { return }
            let missing = scanned.filter { icons[$0.volumeID] == nil }
            if !missing.isEmpty {
                let loaded = await Task.detached(priority: .utility) { VolumeIcons.load(missing) }.value
                guard !Task.isCancelled, generation == token else { return }
                for (id, icon) in loaded { icons[id] = icon.image }
            }
            scanTask = nil
            guard scanned != infos else { return }
            infos = scanned
            publish()
        }
    }

    private func publish() {
        let ids = Set(infos.map(\.volumeID))
        icons = icons.filter { ids.contains($0.key) }
        ejecting.formIntersection(ids)
        items = infos.map { info in
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
