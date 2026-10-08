import AppKit

/// A temporary pin or utility insertion proposal; it never writes preferences.
struct DockDragProposal: Equatable {
    var pins: [DockPin] = []
    let index: Int
    /// When present, index is the destination in the visible utility order after removing the source.
    /// For the App Launcher, index is a stop from ``DockLauncherPlacement/stops(in:)``.
    var utilityID: String? = nil
    /// A volume tile's slot ID. When present, index is the destination among the dock's drives
    /// after removing the source.
    var volumeID: String? = nil
}

/// A stable render identity for either an application or one place in a multi-app insertion gap.
enum DockRenderSlot: Identifiable {
    case launcher
    case focus(FocusDockItem)
    case action(ActionDockItem)
    case melt(AppMeltPair, Int)
    case app(DockItem)
    case folder(FolderDockItem)
    case group(DockGroupControl)
    case sessionCapsule(SessionCapsuleDockItem)
    case sessionCapsules(CapsuleDockItem)
    case shelf(ShelfDockItem)
    case notificationFeed(NotificationFeedDockItem)
    case harbor(HarborDockItem)
    case volume(VolumeDockItem)
    /// Temporary tile for a waiting or freshly installed DOKK update.
    case update(UpdateDockItem)
    case trash(TrashDockItem)
    case gap(String)

    /// The gap that stands in for the App Launcher while it is dragged.
    static let launcherGapID = "launcher"

    var id: String {
        switch self {
        case .melt(let pair, let index): return pair.dockIdentity(at: index).hitID
        case .launcher: return DockEntryID.launcher.hitID
        case .focus: return DockEntryID.focus.hitID
        case .action(let item): return DockEntryID.action(item.tile.id).hitID
        case .app(let item): return "app:\(item.id)"
        case .folder(let item): return item.id
        case .gap(let id): return "gap:\(id)"
        case .group(let control): return DockEntryID.group(control.group).hitID
        case .sessionCapsule(let item): return item.id
        case .sessionCapsules(let item): return item.id
        case .shelf(let item): return item.id
        case .notificationFeed(let item): return item.id
        case .harbor(let item): return item.id
        case .volume(let item): return item.id
        case .update(let item): return item.id
        case .trash(let item): return item.id
        }
    }
    var isPinned: Bool {
        switch self {
        case .app(let item): return item.isFavorite
        case .folder(let item): return !item.isDownloads
        case .gap(let id): return !id.hasPrefix("utility:") && id != Self.launcherGapID
        case .group(let control): return control.group == .pinned
        case .melt, .launcher, .focus, .action, .sessionCapsule, .sessionCapsules, .shelf, .notificationFeed, .harbor, .volume, .update, .trash: return false
        }
    }
    var item: DockItem? { if case .app(let item) = self { return item }; return nil }
    var folder: FolderDockItem? { if case .folder(let item) = self { return item }; return nil }
    var trash: TrashDockItem? { if case .trash(let item) = self { return item }; return nil }
    var shelf: ShelfDockItem? { if case .shelf(let item) = self { return item }; return nil }
    var notificationFeed: NotificationFeedDockItem? { if case .notificationFeed(let item) = self { return item }; return nil }
    var harbor: HarborDockItem? { if case .harbor(let item) = self { return item }; return nil }
    var volume: VolumeDockItem? { if case .volume(let item) = self { return item }; return nil }
    var update: UpdateDockItem? { if case .update(let item) = self { return item }; return nil }
    var capsules: CapsuleDockItem? { if case .sessionCapsules(let item) = self { return item }; return nil }
    var capsule: SessionCapsuleDockItem? { if case .sessionCapsule(let item) = self { return item }; return nil }
    /// Trailing tiles that are neither pins nor running applications, and share one divider.
    var melt: AppMeltPair? { if case .melt(let pair, _) = self { return pair }; return nil }
    var action: ActionDockItem? { if case .action(let item) = self { return item }; return nil }
    var focus: FocusDockItem? { if case .focus(let item) = self { return item }; return nil }
    var isUtility: Bool {
        if case .gap(let id) = self { return id.hasPrefix("utility:") || id == Self.launcherGapID }
        return melt != nil || folder?.isDownloads == true || target == .launcher || focus != nil || action != nil || trash != nil || update != nil || shelf != nil || notificationFeed != nil || harbor != nil || volume != nil || capsules != nil || capsule != nil
    }
    /// The launcher tile, or the gap holding its place during a drag.
    var isLauncher: Bool {
        if case .gap(let id) = self { return id == Self.launcherGapID }
        return target == .launcher
    }
    /// What a drag-to-move gesture carries: a reorderable utility, or the launcher.
    var dragMoveID: String? {
        movableUtilityID ?? (target == .launcher ? id : nil)
    }
    var appGroup: DockAppGroup? {
        switch self {
        case .app(let item): item.isFavorite ? .pinned : .running
        case .folder(let item): item.isDownloads ? nil : .pinned
        case .group(let control): control.group
        case .melt, .launcher, .focus, .action, .sessionCapsule, .sessionCapsules, .shelf, .notificationFeed, .harbor, .volume, .update, .trash, .gap: nil
        }
    }
    var pin: DockPin? {
        switch self {
        case .app(let item) where item.isFavorite: .application(item.reference)
        case .folder(let item) where !item.isDownloads: .folder(item.reference)
        default: nil
        }
    }
    /// Only these built-in tiles can exchange positions in the trailing section.
    var movableUtilityID: String? {
        if folder?.isDownloads == true || capsules != nil || shelf != nil || notificationFeed != nil || harbor != nil { return id }
        return nil
    }

    var icon: NSImage? { item?.icon ?? folder?.icon ?? capsule?.icon ?? capsules?.icon ?? shelf?.icon ?? volume?.icon ?? trash?.icon }
    var name: String {
        switch self {
        case .melt(let pair, let index): pair.names[index]
        case .launcher: String(localized: .launcherTitle)
        case .focus(let item): String(localized: .focusTileName(item.session.modeName))
        case .action(let item): item.tile.name
        case .app(let item): item.reference.name
        case .folder(let item): item.reference.name
        case .group(let control): String(localized: control.title)
        case .sessionCapsule(let item): item.title
        case .sessionCapsules: String(localized: .capsulesName)
        case .shelf: String(localized: .shelfName)
        case .notificationFeed: String(localized: .notificationFeedName)
        case .harbor: String(localized: .harborName)
        case .volume(let item): item.name
        case .update(let item): String(localized: item.title)
        case .trash: String(localized: .trashName)
        case .gap: ""
        }
    }

    var target: DockEntryID? {
        switch self {
        case .melt(let pair, let index): pair.dockIdentity(at: index)
        case .launcher: .launcher
        case .focus: .focus
        case .action(let item): .action(item.tile.id)
        case .app(let item): .app(item.id)
        case .folder(let item): .folder(item.reference.id)
        case .group(let control): .group(control.group)
        case .sessionCapsule(let item): .sessionCapsule(item.capsuleID)
        case .sessionCapsules: .sessionCapsules
        case .shelf: .shelf
        case .notificationFeed: .notificationFeed
        case .harbor: .harbor
        case .volume(let item): .volume(item.volumeID)
        case .update: .update
        case .trash: .trash
        case .gap: nil
        }
    }

    static func slots(items: [DockItem], proposal: DockDragProposal?) -> [DockRenderSlot] {
        slots(entries: items.map(Self.app), proposal: proposal)
    }

    /// Gap indices refer to persisted pins, excluding section controls and incoming duplicates.
    static func slots(entries: [Self], proposal: DockDragProposal?) -> [Self] {
        guard let proposal else { return entries }
        if proposal.utilityID == DockEntryID.launcher.hitID {
            return launcherMoved(entries, to: proposal.index)
        }
        if let utilityID = proposal.utilityID {
            return reordered(entries, moving: utilityID, to: proposal.index) { $0.movableUtilityID != nil }
        }
        if let volumeID = proposal.volumeID {
            return reordered(entries, moving: volumeID, to: proposal.index) { $0.volume != nil }
        }
        let ids = Set(proposal.pins.map(\.id))
        let pins = entries.compactMap(\.pin)
        // Collapsed and hidden pins must never leak into a gap preview.
        if entries.contains(where: { if case .group(let c) = $0 { return c.group == .pinned && !c.expanded }; return false }) { return entries }
        let boundary = pins.prefix(max(0, proposal.index)).filter { !ids.contains($0.id) }.count
        var result = entries.filter { slot in slot.pin.map { !ids.contains($0.id) } ?? true }
        result.insert(contentsOf: proposal.pins.map { .gap($0.id) }, at: pinGapPosition(in: result, boundary: boundary))
        return result
    }

    /// Where a gap after `boundary` remaining pins goes, matching where the dropped pins will render.
    ///
    /// A launcher placed after a pin keeps following that pin, so pins inserted after it land past
    /// the launcher. The gap goes before the next pin, or after the last pin and any launcher
    /// directly behind it.
    private static func pinGapPosition(in result: [Self], boundary: Int) -> Int {
        let pinPositions = result.indices.filter { result[$0].pin != nil }
        if pinPositions.indices.contains(boundary) { return pinPositions[boundary] }
        if let last = pinPositions.last {
            return result.indices.contains(last + 1) && result[last + 1].isLauncher ? last + 2 : last + 1
        }
        return result.prefix { if case .launcher = $0 { return true }; if case .group(let c) = $0 { return c.group == .pinned }; return false }.count
    }

    /// Replaces the launcher with a gap at `stop`, one of ``DockLauncherPlacement/stops(in:)``.
    private static func launcherMoved(_ entries: [Self], to stop: Int) -> [Self] {
        guard let source = entries.firstIndex(where: { $0.target == .launcher }) else { return entries }
        var content = entries
        content.remove(at: source)
        let stops = DockLauncherPlacement.stops(in: content)
        let position = stops[min(max(0, stop), stops.count - 1)]
        return DockLauncherPlacement.entries(content, position: position, pinOrder: []).map {
            $0.target == .launcher ? .gap(launcherGapID) : $0
        }
    }

    /// Moves `sourceID` to a gap at `index` among the slots matching `member`, leaving every other
    /// slot in place. The gap's `utility:` prefix keeps it inside the trailing divider.
    private static func reordered(_ entries: [Self], moving sourceID: String, to index: Int,
                                  member: (Self) -> Bool) -> [Self] {
        let positions = entries.indices.filter { member(entries[$0]) }
        var members = positions.map { entries[$0] }
        guard let source = members.firstIndex(where: { $0.id == sourceID }) else { return entries }
        members.remove(at: source)
        members.insert(.gap("utility:" + sourceID), at: min(max(0, index), members.count))
        var result = entries
        for (position, slot) in zip(positions, members) { result[position] = slot }
        return result
    }
}

/// A connected destination for the accessible copy-pin command. Display names are supplied by macOS.
struct DockPinDestination: Identifiable {
    let id: String
    let name: String
}
