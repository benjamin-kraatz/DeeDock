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
    var deviceProtocol: String?
    /// Disk Arbitration's device model. Mounted disk images report `Disk Image`.
    var deviceModel: String?
}

/// Reads mounted volumes. Every call does file system I/O, which can stall on a slow network
/// share, so callers run it off the main actor.
nonisolated enum VolumeScanner {
    private static let keys: [URLResourceKey] = [
        .volumeIsBrowsableKey, .volumeIsRootFileSystemKey, .volumeIsLocalKey, .volumeIsInternalKey,
        .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeLocalizedNameKey, .volumeUUIDStringKey,
        .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey
    ]

    /// Every user-visible volume that qualifies as removable, external, a disk image, or a share,
    /// in Finder's mount order.
    static func scan() -> [VolumeInfo] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                          options: [.skipHiddenVolumes]) ?? []
        let session = DASessionCreate(kCFAllocatorDefault)
        return urls.compactMap { info(for: $0, session: session) }
    }

    /// Reads one volume, or nil when it does not belong in the dock.
    static func info(for url: URL, session: DASession? = DASessionCreate(kCFAllocatorDefault)) -> VolumeInfo? {
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
        let description = session.flatMap { session in
            DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL)
        }.flatMap { DADiskCopyDescription($0) as? [String: Any] }
        let traits = VolumeTraits(
            path: url.standardizedFileURL.path,
            isBrowsable: values.volumeIsBrowsable ?? false,
            isRootFileSystem: values.volumeIsRootFileSystem ?? false,
            isLocal: values.volumeIsLocal ?? true,
            isInternal: values.volumeIsInternal ?? false,
            isRemovable: values.volumeIsRemovable ?? false,
            isEjectable: values.volumeIsEjectable ?? false,
            deviceProtocol: description?[kDADiskDescriptionDeviceProtocolKey as String] as? String,
            deviceModel: description?[kDADiskDescriptionDeviceModelKey as String] as? String)
        guard let kind = classify(traits) else { return nil }
        let name = values.volumeLocalizedName ?? url.lastPathComponent
        let available = VolumeCapacityFormat.available(important: values.volumeAvailableCapacityForImportantUsage,
                                                       plain: values.volumeAvailableCapacity.map(Int64.init))
        return VolumeInfo(volumeID: values.volumeUUIDString ?? "path:\(traits.path)", url: url, name: name, kind: kind,
                          totalCapacity: values.volumeTotalCapacity.map(Int64.init), availableCapacity: available)
    }

    /// Maps volume traits to a dock kind. The boot volume, hidden system volumes, and internal
    /// partitions never appear; only what a user can plug in, mount, or eject does.
    static func classify(_ traits: VolumeTraits) -> VolumeKind? {
        guard traits.isBrowsable, !traits.isRootFileSystem, traits.path.hasPrefix("/Volumes/") else { return nil }
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
}
