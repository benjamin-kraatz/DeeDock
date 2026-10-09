import AppKit
import Observation

/// Mounted volumes for the Files sidebar.
///
/// Reads the boot volume and every browsable mount under `/Volumes` (internal partitions, disks,
/// disk images, and shares) and refreshes on NSWorkspace mount, unmount, and rename
/// notifications. Reads run on `VolumeReads`, local volumes first, so a wedged share never delays
/// the others. Observers are removed by `stop()` and on deinit.
@MainActor @Observable
final class HubVolumes {
    /// One mounted volume.
    nonisolated struct Volume: Identifiable, Hashable, Sendable {
        let url: URL
        var id: URL { url }
        /// Localized volume name supplied by macOS.
        let name: String
        let availableBytes: Int64?
        let totalBytes: Int64?
        /// True when the volume can be unmounted from the sidebar: removable and external disks,
        /// disk images, and network shares. Never the boot volume.
        let isEjectable: Bool
        let isInternal: Bool
    }

    /// Why an eject failed, with a localized description for an alert.
    nonisolated enum EjectError: LocalizedError, Equatable {
        /// Apps hold files open on the volume. `blockers` may be empty when macOS named none.
        case blocked(volumeName: String, blockers: [VolumeBlocker])
        case failed(volumeName: String, reason: String)

        var errorDescription: String? {
            switch self {
            case let .blocked(name, blockers):
                guard !blockers.isEmpty else { return String(localized: .hubFilesEjectBlocked(name)) }
                let names = ListFormatter.localizedString(byJoining: blockers.map(\.name))
                return String(localized: .hubFilesEjectBlockedBy(name, names))
            case let .failed(name, reason):
                return String(localized: .hubFilesEjectFailed(name, reason))
            }
        }
    }

    /// Boot volume first, then the others by name.
    private(set) var volumes: [Volume] = []
    /// Volumes with an eject in flight. The sidebar dims them and spins the eject glyph.
    private(set) var ejecting: Set<URL> = []

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var scan: Task<Void, Never>?

    nonisolated init() {}

    /// Reads volumes and starts observing mounts. Calling it while running only rescans.
    func start() {
        if observers.isEmpty {
            let center = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
                         NSWorkspace.didRenameVolumeNotification] {
                observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.rescan() }
                })
            }
        }
        rescan()
    }

    /// Stops observing and cancels a scan in progress. Keeps the last list.
    func stop() {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
        scan?.cancel()
        scan = nil
    }

    /// Unmounts `volume` and ejects its device, like Finder's Eject, without system UI.
    /// - Throws: `EjectError.blocked` when apps hold files open, `EjectError.failed` otherwise.
    func eject(_ volume: Volume) async throws {
        guard !ejecting.contains(volume.url) else { return }
        ejecting.insert(volume.url)
        defer { ejecting.remove(volume.url) }
        switch await VolumeEjector.eject(volume.url) {
        case .ejected:
            volumes.removeAll { $0.url == volume.url }
        case .blocked(let blockers):
            throw EjectError.blocked(volumeName: volume.name, blockers: blockers)
        case .failed(let reason):
            throw EjectError.failed(volumeName: volume.name, reason: reason)
        }
    }

    private func rescan() {
        scan?.cancel()
        scan = Task { [weak self] in
            let mounts = VolumeScanner.mounts()
            let root = URL(fileURLWithPath: "/", isDirectory: true)
            let local = [root] + mounts.filter(\.isLocal).map(\.url)
            let shares = mounts.filter { !$0.isLocal }.map(\.url)
            let localVolumes = await VolumeReads.run(qos: .userInitiated) { local.compactMap(Self.read) }
            guard let self, !Task.isCancelled else { return }
            self.volumes = Self.ordered(localVolumes)
            guard !shares.isEmpty else { return }
            // Shares last: a wedged server can stall this read for minutes.
            let shareVolumes = await VolumeReads.run { shares.compactMap(Self.read) }
            guard !Task.isCancelled else { return }
            self.volumes = Self.ordered(localVolumes + shareVolumes)
        }
    }

    /// Boot volume first, then by localized name.
    nonisolated static func ordered(_ volumes: [Volume]) -> [Volume] {
        volumes.sorted { a, b in
            let (ra, rb) = (a.url.path == "/", b.url.path == "/")
            if ra != rb { return ra }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// Reads one volume. Does file-system I/O; run on `VolumeReads`.
    nonisolated private static func read(_ url: URL) -> Volume? {
        let keys: Set<URLResourceKey> = [
            .volumeLocalizedNameKey, .volumeIsRootFileSystemKey, .volumeIsInternalKey, .volumeIsLocalKey,
            .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsBrowsableKey,
            .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys), values.volumeIsBrowsable != false else { return nil }
        let isRoot = values.volumeIsRootFileSystem ?? (url.path == "/")
        let isInternal = values.volumeIsInternal ?? false
        let isLocal = values.volumeIsLocal ?? true
        let canEject = values.volumeIsEjectable == true || values.volumeIsRemovable == true || !isLocal || !isInternal
        return Volume(
            url: url,
            name: values.volumeLocalizedName ?? FileManager.default.displayName(atPath: url.path),
            availableBytes: VolumeCapacityFormat.available(
                important: values.volumeAvailableCapacityForImportantUsage,
                plain: values.volumeAvailableCapacity.map(Int64.init)),
            totalBytes: values.volumeTotalCapacity.map(Int64.init),
            isEjectable: !isRoot && canEject,
            isInternal: isInternal)
    }

    isolated deinit { stop() }
}
