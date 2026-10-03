import AppKit
import CryptoKit

/// The categories of mounted volume a dock can show, each with its own Settings switch.
nonisolated enum VolumeKind: String, Equatable, Sendable {
    /// Removable media such as USB sticks and SD cards.
    case removable
    /// An external disk whose media is fixed, typically a drive that stays connected.
    case externalDisk
    /// A mounted disk image (`.dmg`, `.sparsebundle`, …).
    case diskImage
    /// A file server share mounted over the network.
    case network

    /// Symbol drawn in the tile's corner badge so the kind is recognizable at dock size.
    var badgeSymbol: String {
        switch self {
        case .removable: "mediastick"
        case .externalDisk: "externaldrive.fill"
        case .diskImage: "opticaldisc.fill"
        case .network: "network"
        }
    }
}

/// What the scanner read about one mounted volume. Pure data, safe to produce off the main actor.
nonisolated struct VolumeInfo: Equatable, Sendable {
    /// Stable identity across remounts: the file system UUID, or the mount path when there is none.
    let volumeID: String
    let url: URL
    /// Finder's display name for the volume.
    let name: String
    let kind: VolumeKind
    var totalCapacity: Int64?
    var availableCapacity: Int64?
}

/// Which kinds of volume the docks include, resolved from the shared Feature settings.
nonisolated struct VolumeVisibility: Equatable, Sendable {
    var showsVolumes: Bool
    var showsDiskImages: Bool
    var showsNetworkVolumes: Bool

    static let hidden = VolumeVisibility(showsVolumes: false, showsDiskImages: false, showsNetworkVolumes: false)

    init(showsVolumes: Bool, showsDiskImages: Bool, showsNetworkVolumes: Bool) {
        self.showsVolumes = showsVolumes
        self.showsDiskImages = showsDiskImages
        self.showsNetworkVolumes = showsNetworkVolumes
    }

    init(settings: DockSettings) {
        self.init(showsVolumes: settings.showVolumes, showsDiskImages: settings.showDiskImages,
                  showsNetworkVolumes: settings.showNetworkVolumes)
    }

    /// The master switch gates every kind; disk images and network shares have their own opt-ins.
    func includes(_ kind: VolumeKind) -> Bool {
        guard showsVolumes else { return false }
        switch kind {
        case .removable, .externalDisk: return true
        case .diskImage: return showsDiskImages
        case .network: return showsNetworkVolumes
        }
    }
}

/// A rendered volume tile. One snapshot is shared by every display dock.
struct VolumeDockItem: Identifiable {
    let info: VolumeInfo
    let icon: NSImage
    /// True from the moment an eject starts until it succeeds or fails. The tile dims meanwhile.
    let isEjecting: Bool

    var id: String { "volume:\(info.volumeID)" }
    var volumeID: String { info.volumeID }
    var name: String { info.name }
    var url: URL { info.url }
    var kind: VolumeKind { info.kind }

    /// Folder-stack identity for this volume. Derived from `volumeID`, so a remounted stick keeps
    /// its stack sort and presentation.
    var stackID: UUID { VolumeStackIdentity.uuid(for: info.volumeID) }

    /// Presents the volume's root through the folder-stack popover. Presentation is stored per
    /// display, like Downloads, because a volume is never a saved pin.
    func stackItem(displayID: String) -> FolderDockItem {
        let presentation = UserDefaults.standard.string(forKey: VolumeStackIdentity.presentationKey(displayID: displayID, stackID: stackID))
            .flatMap(FolderStackPresentation.init(rawValue:)) ?? .grid
        let reference = FolderReference(id: stackID, url: url, name: name, bookmarkData: Data(), presentation: presentation)
        return FolderDockItem(reference: reference, icon: icon, isAvailable: !isEjecting)
    }
}

/// Stable folder-stack identities for volumes, which have no saved pin to carry a UUID.
nonisolated enum VolumeStackIdentity {
    /// Uses the file system UUID directly when it is one. Otherwise derives a deterministic UUID
    /// from the identity string, so FAT sticks without a UUID still map to the same stack.
    static func uuid(for volumeID: String) -> UUID {
        if let uuid = UUID(uuidString: volumeID) { return uuid }
        var bytes = Array(Insecure.MD5.hash(data: Data(volumeID.utf8)))
        bytes[6] = (bytes[6] & 0x0F) | 0x30 // Version 3 (name-based, MD5).
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant.
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    static func presentationKey(displayID: String, stackID: UUID) -> String {
        "volumePresentation.\(displayID).\(stackID.uuidString)"
    }
}

/// A process that has files open on a volume, reduced to what the card can name and act on.
nonisolated struct VolumeBlocker: Identifiable, Equatable, Sendable {
    /// The application's process, or the bare process when no application owns it.
    let pid: pid_t
    /// Application name supplied by macOS, or the process name (for example `zsh`).
    let name: String
    /// True when `pid` belongs to a regular application that can be shown or asked to quit.
    let isApplication: Bool
    /// The program file of a bare process, for Show in Finder. Nil for applications.
    var executablePath: String? = nil
    /// True for a process that runs as another user and belongs to macOS.
    var isSystem = false
    var id: pid_t { pid }
}

/// The outcome of one eject attempt.
nonisolated enum VolumeEjectResult: Equatable, Sendable {
    case ejected
    /// macOS refused because these processes still have files open. Empty when macOS named none
    /// that DOKK can see.
    case blocked([VolumeBlocker])
    case failed(String)
}

/// Formats capacities the way Finder does: decimal units, "128 GB".
nonisolated enum VolumeCapacityFormat {
    static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Free space to show. The important-usage figure adds purgeable space on APFS, but FAT32 and
    /// exFAT (most USB sticks and SD cards) report it as 0 while the plain figure is correct, so
    /// the larger of the two wins.
    static func available(important: Int64?, plain: Int64?) -> Int64? {
        switch (important, plain) {
        case let (important?, plain?): max(important, plain)
        case let (important?, nil): important
        case let (nil, plain?): plain
        case (nil, nil): nil
        }
    }

    /// Fraction of the volume in use, clamped to 0...1, or nil when either value is unknown.
    static func usedFraction(total: Int64?, available: Int64?) -> Double? {
        guard let total, let available, total > 0 else { return nil }
        return min(max(Double(total - available) / Double(total), 0), 1)
    }
}
