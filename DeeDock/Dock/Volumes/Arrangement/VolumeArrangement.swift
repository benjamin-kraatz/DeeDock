import Foundation

/// One drive DOKK has seen, remembered so its place and visibility survive unplugging.
nonisolated struct VolumeArrangementEntry: Codable, Equatable, Identifiable, Sendable {
    /// Matches `VolumeInfo.volumeID`: the file system UUID, or the mount path when there is none.
    let volumeID: String
    /// Finder's name from the last mount, so Settings can list the drive while it is disconnected.
    var name: String
    var kind: VolumeKind
    /// A hidden drive stays mounted and keeps its place, but no dock shows a tile for it.
    var isHidden: Bool
    /// When the drive last arrived or left. Settings shows it for a disconnected drive, and
    /// pruning forgets the stalest disconnected drives first.
    var lastSeen: Date

    var id: String { volumeID }
}

/// The user's order and visibility for drives, shared by every dock.
///
/// `entries` order is dock order. Drives seen for the first time join at the end. Disconnected
/// drives keep their entry, so a stick plugged back in returns to the same place, until the list
/// outgrows `capacity`.
nonisolated struct VolumeArrangement: Codable, Equatable, Sendable {
    /// The most drives remembered. Hidden and mounted drives are never pruned, so the list can
    /// exceed this only when the user hides more drives than this.
    static let capacity = 64

    private(set) var entries: [VolumeArrangementEntry] = []

    init(entries: [VolumeArrangementEntry] = []) {
        self.entries = entries
    }

    func isHidden(_ volumeID: String) -> Bool {
        entries.first { $0.volumeID == volumeID }?.isHidden ?? false
    }

    /// Records the mounted volumes. New drives join at the end in mount order. Drives that arrived
    /// or left since `previouslyMounted` get `date` as their last-seen time, and known drives pick
    /// up a renamed volume's name.
    mutating func remember(_ volumes: [VolumeInfo], previouslyMounted: Set<String>, at date: Date) {
        let mounted = Set(volumes.map(\.volumeID))
        for volume in volumes {
            if let index = entries.firstIndex(where: { $0.volumeID == volume.volumeID }) {
                entries[index].name = volume.name
                entries[index].kind = volume.kind
                if !previouslyMounted.contains(volume.volumeID) { entries[index].lastSeen = date }
            } else {
                entries.append(VolumeArrangementEntry(volumeID: volume.volumeID, name: volume.name, kind: volume.kind,
                                                      isHidden: false, lastSeen: date))
            }
        }
        for id in previouslyMounted.subtracting(mounted) {
            if let index = entries.firstIndex(where: { $0.volumeID == id }) { entries[index].lastSeen = date }
        }
        prune(keeping: mounted)
    }

    /// `volumes` in arrangement order. Volumes without an entry keep their relative order at the end.
    func arranged<Volume>(_ volumes: [Volume], id: (Volume) -> String) -> [Volume] {
        let positions = Dictionary(entries.enumerated().map { ($1.volumeID, $0) }, uniquingKeysWith: { first, _ in first })
        return volumes.enumerated().sorted { lhs, rhs in
            let left = positions[id(lhs.element)] ?? entries.count + lhs.offset
            let right = positions[id(rhs.element)] ?? entries.count + rhs.offset
            return left < right
        }.map(\.element)
    }

    /// Returns false when the drive is unknown or already in that state.
    @discardableResult
    mutating func setHidden(_ volumeID: String, _ hidden: Bool) -> Bool {
        guard let index = entries.firstIndex(where: { $0.volumeID == volumeID }),
              entries[index].isHidden != hidden else { return false }
        entries[index].isHidden = hidden
        return true
    }

    mutating func forget(_ volumeID: String) {
        entries.removeAll { $0.volumeID == volumeID }
    }

    /// Moves `volumeID` to `index` in `sequence`, an ordered subset of the entries that contains it,
    /// such as the drives one dock shows. `index` counts positions in `sequence` with `volumeID`
    /// removed, as dock insertion gaps do. The drive lands just before the drive now at `index`,
    /// or just after the last one, so entries outside `sequence` keep their neighbors.
    mutating func move(_ volumeID: String, to index: Int, within sequence: [String]) {
        guard sequence.contains(volumeID), let source = entries.firstIndex(where: { $0.volumeID == volumeID }) else { return }
        let others = sequence.filter { $0 != volumeID }
        let target = min(max(0, index), others.count)
        let entry = entries.remove(at: source)
        let destination: Int
        if target < others.count, let before = entries.firstIndex(where: { $0.volumeID == others[target] }) {
            destination = before
        } else if let last = others.last, let after = entries.firstIndex(where: { $0.volumeID == last }) {
            destination = after + 1
        } else {
            destination = source
        }
        entries.insert(entry, at: min(destination, entries.count))
    }

    /// Forgets the drives disconnected longest, sparing hidden ones and anything in `mounted`.
    private mutating func prune(keeping mounted: Set<String>) {
        let excess = entries.count - Self.capacity
        guard excess > 0 else { return }
        let stale = entries.filter { !$0.isHidden && !mounted.contains($0.volumeID) }
            .sorted { $0.lastSeen < $1.lastSeen }
            .prefix(excess)
            .map(\.volumeID)
        let forgotten = Set(stale)
        entries.removeAll { forgotten.contains($0.volumeID) }
    }
}
