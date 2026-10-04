import DiskArbitration
import Foundation

/// The facts that decide whether, and as what, a mounted volume appears in the dock.
nonisolated struct VolumeTraits: Equatable, Sendable {
    var path: String
    var isBrowsable: Bool
    var isRootFileSystem: Bool
    var isLocal: Bool
    var isInternal: Bool
    var isRemovable: Bool
    var isEjectable: Bool
    /// Disk Arbitration's device protocol, such as `USB`, `Thunderbolt`, or `Disk Image`.
    var deviceProtocol: String? = nil
    /// Disk Arbitration's device model. Mounted disk images report `Disk Image`.
    var deviceModel: String? = nil
    /// True when Time Machine uses the volume as a backup destination.
    var isTimeMachineBackup = false
}

/// A mount point as the kernel last recorded it. Listing these never contacts a file server.
nonisolated struct MountedVolume: Equatable, Sendable {
    let url: URL
    /// The mount's `MNT_LOCAL` flag, the same source `volumeIsLocalKey` reads. False for a share.
    let isLocal: Bool
}

/// Reads mounted volumes. Apart from `mounts()`, every call does file system I/O, which can
/// stall on a slow network share, so callers run it through `VolumeReads`.
nonisolated enum VolumeScanner {
    private static let keys: [URLResourceKey] = [
        .volumeIsBrowsableKey, .volumeIsRootFileSystemKey, .volumeIsLocalKey, .volumeIsInternalKey,
        .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeLocalizedNameKey, .volumeUUIDStringKey,
        .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey
    ]

    /// Browsable mounts under `/Volumes`, in mount order.
    ///
    /// `MNT_NOWAIT` returns the statistics the kernel already holds instead of asking each file
    /// system for fresh ones, so a wedged share cannot stall the listing. That lets callers read
    /// and publish local volumes before they touch any share.
    static func mounts() -> [MountedVolume] {
        var table: UnsafeMutablePointer<statfs>?
        let count = getmntinfo_r_np(&table, MNT_NOWAIT)
        defer { free(table) }
        guard count > 0, let table else { return [] }
        return UnsafeBufferPointer(start: table, count: Int(count)).compactMap { entry in
            let path = withUnsafeBytes(of: entry.f_mntonname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            // The same gates `isCandidate` applies, checked here so other mounts are never read.
            guard path.hasPrefix("/Volumes/"), entry.f_flags & UInt32(MNT_DONTBROWSE) == 0 else { return nil }
            return MountedVolume(url: URL(fileURLWithPath: path, isDirectory: true),
                                 isLocal: entry.f_flags & UInt32(MNT_LOCAL) != 0)
        }
    }

    /// The given mounts that qualify as removable, external, a disk image, or a share, in the
    /// order given.
    static func scan(_ mounts: [MountedVolume]) -> [VolumeInfo] {
        let session = DASessionCreate(kCFAllocatorDefault)
        return mounts.compactMap { info(for: $0.url, session: session) }
    }

    /// `volumes` in the order of `mounts`, without any whose mount is gone.
    static func ordered(_ volumes: [VolumeInfo], by mounts: [MountedVolume]) -> [VolumeInfo] {
        let byURL = Dictionary(volumes.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        return mounts.compactMap { byURL[$0.url] }
    }

    /// Reads one volume, or nil when it does not belong in the dock.
    static func info(for url: URL, session: DASession? = DASessionCreate(kCFAllocatorDefault)) -> VolumeInfo? {
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
        var traits = VolumeTraits(
            path: url.standardizedFileURL.path,
            isBrowsable: values.volumeIsBrowsable ?? false,
            isRootFileSystem: values.volumeIsRootFileSystem ?? false,
            isLocal: values.volumeIsLocal ?? true,
            isInternal: values.volumeIsInternal ?? false,
            isRemovable: values.volumeIsRemovable ?? false,
            isEjectable: values.volumeIsEjectable ?? false)
        // Disk Arbitration and the backup check both touch the volume, so a mount `classify` is
        // certain to drop never pays for them.
        guard isCandidate(traits) else { return nil }
        let description = session.flatMap { session in
            DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL)
        }.flatMap { DADiskCopyDescription($0) as? [String: Any] }
        traits.deviceProtocol = description?[kDADiskDescriptionDeviceProtocolKey as String] as? String
        traits.deviceModel = description?[kDADiskDescriptionDeviceModelKey as String] as? String
        traits.isTimeMachineBackup = isTimeMachineBackup(url)
        guard let kind = classify(traits) else { return nil }
        let name = values.volumeLocalizedName ?? url.lastPathComponent
        let available = VolumeCapacityFormat.available(important: values.volumeAvailableCapacityForImportantUsage,
                                                       plain: values.volumeAvailableCapacity.map(Int64.init))
        return VolumeInfo(volumeID: values.volumeUUIDString ?? "path:\(traits.path)", url: url, name: name, kind: kind,
                          totalCapacity: values.volumeTotalCapacity.map(Int64.init), availableCapacity: available)
    }

    /// Whether a volume can appear at all: browsable, not the boot volume, and under `/Volumes`.
    static func isCandidate(_ traits: VolumeTraits) -> Bool {
        traits.isBrowsable && !traits.isRootFileSystem && traits.path.hasPrefix("/Volumes/")
    }

    /// Maps volume traits to a dock kind. The boot volume, hidden system volumes, and internal
    /// partitions never appear; only what a user can plug in, mount, or eject does.
    static func classify(_ traits: VolumeTraits) -> VolumeKind? {
        guard isCandidate(traits) else { return nil }
        // Checked first: a backup destination can also be a disk image or an ejectable disk.
        if traits.isTimeMachineBackup { return .timeMachine }
        if !traits.isLocal { return .network }
        // Disk Arbitration names disk images by model; older systems used the protocol instead.
        let imageMarkers: Set<String> = ["Disk Image", "Virtual Interface"]
        if traits.deviceModel.map(imageMarkers.contains) == true
            || traits.deviceProtocol.map(imageMarkers.contains) == true {
            return .diskImage
        }
        if traits.isInternal { return nil }
        if traits.isRemovable { return .removable }
        if traits.isEjectable || traits.deviceProtocol != nil { return .externalDisk }
        return nil
    }

    /// Whether Time Machine backs up to the volume mounted at `url`.
    ///
    /// The backup service tags an APFS destination's root with `com.apple.backupd.*` and
    /// `com.apple.timemachine.*` extended attributes, and an HFS+ destination holds
    /// `Backups.backupdb`. Attribute names stay readable without Full Disk Access, even though
    /// the volume's contents do not, so this never needs the access it is used to detect.
    static func isTimeMachineBackup(_ url: URL) -> Bool {
        let path = url.path
        let size = listxattr(path, nil, 0, 0)
        if size > 0 {
            var buffer = [CChar](repeating: 0, count: size)
            let length = listxattr(path, &buffer, size, 0)
            if length > 0, isTimeMachineBackup(attributeNames: buffer.prefix(length).split(separator: 0).map {
                String(decoding: $0.map(UInt8.init(bitPattern:)), as: UTF8.self)
            }) {
                return true
            }
        }
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("Backups.backupdb").path)
    }

    /// Whether a volume root's extended attribute names include a Time Machine destination marker.
    static func isTimeMachineBackup(attributeNames: [String]) -> Bool {
        attributeNames.contains { $0.hasPrefix("com.apple.backupd.") || $0.hasPrefix("com.apple.timemachine.") }
    }
}

/// Runs volume reads on a private dispatch queue instead of the Swift concurrency thread pool.
///
/// A read on a wedged network share can block in the kernel for minutes. On a dispatch thread
/// that stalls only the read; on the cooperative pool it would hold one of the few threads every
/// task in the app shares.
nonisolated enum VolumeReads {
    private static let queue = DispatchQueue(label: "DeeDock.VolumeReads", qos: .utility, attributes: .concurrent)

    /// Returns `read`'s result. Cancelling the caller does not interrupt a read in progress.
    static func run<Value: Sendable>(qos: DispatchQoS = .utility,
                                     _ read: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            queue.async(qos: qos) { continuation.resume(returning: read()) }
        }
    }
}
