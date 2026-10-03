import Foundation

/// One automatically recognized band of dock items.
///
/// Islands follow the order the dock already uses. Pinned apps stay together, running apps stay
/// together, and trailing tiles split into extras, drives, and the Trash. A leading App Launcher
/// is its own extras island when pinned apps follow it, because the two bands are not contiguous.
enum DockIslandRole: String, Codable, CaseIterable, Equatable, Sendable {
    case pinned, running, extras, drives, trash

    var title: LocalizedStringResource {
        switch self {
        case .pinned: .islandsPinned
        case .running: .islandsRunning
        case .extras: .islandsExtras
        case .drives: .islandsDrives
        case .trash: .islandsTrash
        }
    }
}

/// A dock tile reduced to the identity an island editor can store.
///
/// Icons and live controllers stay on the dock. Settings only needs a stable id, the name macOS
/// supplied, and the section the tile would join before any edit.
struct DockIslandSlotSnapshot: Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var role: DockIslandRole
    /// Section controls stay with their apps and are not items a person moves between islands.
    var isGroup: Bool
}

/// One glass section on a display.
///
/// `name` empty means the localized role title, or "Island" when the section has no role.
/// `accepts` is the automatic home for tiles of that role that nobody has moved yet.
/// `memberIDs` are tiles a person placed here. Membership wins over `accepts`.
struct DockIsland: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var accepts: DockIslandRole?
    var memberIDs: [String]
}

/// Per-display island layout.
///
/// `customized` false means the dock still generates sections from the current tiles.
/// The first edit copies that generation into `islands` so later launches keep the edit.
struct DockIslandDocument: Codable, Equatable, Sendable {
    var customized = false
    var islands: [DockIsland] = []

    static let automatic = DockIslandDocument()
    static let maximumIslands = 24
}

/// How an island is named before the string is resolved for the current language.
enum DockIslandTitle: Equatable, Sendable {
    case role(DockIslandRole)
    case launcher
    case text(String)
}

/// One island as Settings shows it, including only the tiles currently on that dock.
struct DockIslandEditorIsland: Equatable, Identifiable, Sendable {
    var id: String
    var storedName: String
    var accepts: DockIslandRole?
    var title: DockIslandTitle
    var members: [DockIslandSlotSnapshot]
    /// False for a band that only exists because its section was deleted. Those tiles stay listed
    /// so they can move onto a saved island; the band itself cannot be renamed or reordered.
    var canEdit: Bool
}

/// Geometry and accessibility for one run of tiles that share a glass capsule.
struct DockIslandBreak: Equatable, Sendable {
    var start: Int
    var title: DockIslandTitle
}

/// Builds and edits the glass sections without reading preferences or drawing.
enum DockIslandArrangement {
    /// Section a tile belongs to before the user moves it.
    static func role(of slot: DockRenderSlot) -> DockIslandRole {
        switch slot {
        case .trash: .trash
        case .volume: .drives
        case .group(let control): control.group == .pinned ? .pinned : .running
        case .app(let item): item.isFavorite ? .pinned : .running
        case .folder(let item): item.isDownloads ? .extras : .pinned
        case .melt: .running
        case .launcher, .focus, .action, .sessionCapsule, .sessionCapsules, .shelf, .gap:
            .extras
        }
    }

    static func snapshot(of slot: DockRenderSlot) -> DockIslandSlotSnapshot? {
        if case .gap = slot { return nil }
        let isGroup: Bool
        if case .group = slot { isGroup = true } else { isGroup = false }
        return DockIslandSlotSnapshot(id: slot.id, name: slot.name, role: role(of: slot), isGroup: isGroup)
    }

    /// Leaves `slots` in their current order. Automatic islands are a drawing concern.
    static func arrangedSlots(_ slots: [DockRenderSlot], document: DockIslandDocument) -> [DockRenderSlot] {
        guard document.customized, !document.islands.isEmpty else { return slots }
        let explicit = explicitIndex(in: document.islands)
        var used = Set<String>()
        var result: [DockRenderSlot] = []
        for index in document.islands.indices {
            var chunk: [DockRenderSlot] = []
            for slot in slots {
                if case .gap = slot { continue }
                guard !used.contains(slot.id),
                      islandIndex(of: slot, islands: document.islands, explicit: explicit) == index else { continue }
                used.insert(slot.id)
                chunk.append(slot)
            }
            result.append(contentsOf: chunk)
        }
        let leftovers = slots.filter { slot in
            if case .gap = slot { return false }
            return !used.contains(slot.id)
        }
        result.append(contentsOf: leftovers)
        return result
    }

    /// Island boundaries for the slots the dock is about to draw, including drag gaps.
    static func breaks(in slots: [DockRenderSlot], document: DockIslandDocument) -> [DockIslandBreak] {
        if document.customized, !document.islands.isEmpty {
            return customBreaks(in: slots, islands: document.islands)
        }
        return automaticBreaks(in: slots)
    }

    /// The sections Settings lists. Empty custom islands stay so a person can move tiles into them.
    static func editorIslands(snapshots: [DockIslandSlotSnapshot], document: DockIslandDocument) -> [DockIslandEditorIsland] {
        if !document.customized {
            return automaticEditorIslands(snapshots)
        }
        let explicit = explicitIndex(in: document.islands)
        var claimed = Set<String>()
        var rows: [DockIslandEditorIsland] = []
        for (index, island) in document.islands.enumerated() {
            let members = snapshots.filter { snapshot in
                guard !snapshot.isGroup, islandIndex(of: snapshot, islands: document.islands, explicit: explicit) == index,
                      claimed.insert(snapshot.id).inserted else { return false }
                return true
            }
            rows.append(DockIslandEditorIsland(id: island.id, storedName: island.name, accepts: island.accepts,
                                                title: storedTitle(island), members: members, canEdit: true))
        }
        let leftovers = snapshots.filter { !$0.isGroup && !claimed.contains($0.id) }
        var roleRuns: [(DockIslandRole, [DockIslandSlotSnapshot])] = []
        for snapshot in leftovers {
            if let last = roleRuns.last, last.0 == snapshot.role {
                roleRuns[roleRuns.count - 1].1.append(snapshot)
            } else {
                roleRuns.append((snapshot.role, [snapshot]))
            }
        }
        for (offset, run) in roleRuns.enumerated() {
            rows.append(DockIslandEditorIsland(id: "leftover-\(offset)-\(run.0.rawValue)", storedName: "",
                                                accepts: run.0, title: .role(run.0), members: run.1, canEdit: false))
        }
        return rows
    }

    /// Copies the current automatic sections into an editable document. Later edits keep those ids.
    static func materialize(_ snapshots: [DockIslandSlotSnapshot]) -> DockIslandDocument {
        let rows = automaticEditorIslands(snapshots)
        let islands = rows.map { row in
            DockIsland(id: row.id, name: "", accepts: row.accepts, memberIDs: row.members.map(\.id))
        }
        return DockIslandDocument(customized: true, islands: islands)
    }

    static func renaming(_ document: DockIslandDocument, islandID: String, to name: String,
                         snapshots: [DockIslandSlotSnapshot]) -> DockIslandDocument {
        var document = editable(document, snapshots: snapshots)
        let trimmed = String(name.prefix(40))
        guard let index = document.islands.firstIndex(where: { $0.id == islandID }) else { return document }
        document.islands[index].name = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        return document
    }

    static func movingIsland(_ document: DockIslandDocument, id: String, by distance: Int,
                             snapshots: [DockIslandSlotSnapshot]) -> DockIslandDocument {
        var document = editable(document, snapshots: snapshots)
        guard let index = document.islands.firstIndex(where: { $0.id == id }) else { return document }
        let destination = index + distance
        guard document.islands.indices.contains(destination) else { return document }
        let island = document.islands.remove(at: index)
        document.islands.insert(island, at: destination)
        return document
    }

    /// Places `memberID` on `islandID`. Tiles of its old role stop following it automatically.
    static func movingMember(_ document: DockIslandDocument, memberID: String, to islandID: String,
                             snapshots: [DockIslandSlotSnapshot]) -> DockIslandDocument {
        var document = editable(document, snapshots: snapshots)
        guard document.islands.contains(where: { $0.id == islandID }) else { return document }
        for index in document.islands.indices {
            document.islands[index].memberIDs.removeAll { $0 == memberID }
        }
        guard let destination = document.islands.firstIndex(where: { $0.id == islandID }) else { return document }
        document.islands[destination].memberIDs.append(memberID)
        return document
    }

    static func addingIsland(_ document: DockIslandDocument, snapshots: [DockIslandSlotSnapshot]) -> DockIslandDocument {
        var document = editable(document, snapshots: snapshots)
        guard document.islands.count < DockIslandDocument.maximumIslands else { return document }
        document.islands.append(DockIsland(id: "island-\(UUID().uuidString)", name: "", accepts: nil, memberIDs: []))
        return document
    }

    /// Removes an island and keeps its tiles on a neighbor, so nothing disappears from the dock.
    static func deletingIsland(_ document: DockIslandDocument, id: String,
                               snapshots: [DockIslandSlotSnapshot]) -> DockIslandDocument {
        var document = editable(document, snapshots: snapshots)
        guard document.islands.count > 1, let index = document.islands.firstIndex(where: { $0.id == id }) else { return document }
        let removed = document.islands.remove(at: index)
        let host = min(index, document.islands.count - 1)
        var members = document.islands[host].memberIDs
        for member in removed.memberIDs where !members.contains(member) { members.append(member) }
        document.islands[host].memberIDs = members
        if document.islands[host].accepts == nil { document.islands[host].accepts = removed.accepts }
        return document
    }

    private static func editable(_ document: DockIslandDocument, snapshots: [DockIslandSlotSnapshot]) -> DockIslandDocument {
        document.customized ? document : materialize(snapshots)
    }

    private static func automaticEditorIslands(_ snapshots: [DockIslandSlotSnapshot]) -> [DockIslandEditorIsland] {
        var runs: [(role: DockIslandRole, members: [DockIslandSlotSnapshot])] = []
        for snapshot in snapshots where !snapshot.isGroup {
            if let last = runs.last, last.role == snapshot.role {
                runs[runs.count - 1].members.append(snapshot)
            } else {
                runs.append((snapshot.role, [snapshot]))
            }
        }
        return runs.enumerated().map { index, run in
            let title: DockIslandTitle = run.members.count == 1 && run.members[0].id == DockEntryID.launcher.hitID
                ? .launcher : .role(run.role)
            return DockIslandEditorIsland(id: "auto-\(index)", storedName: "", accepts: run.role,
                                           title: title, members: run.members, canEdit: true)
        }
    }

    private static func automaticBreaks(in slots: [DockRenderSlot]) -> [DockIslandBreak] {
        let roles = gapRoles(in: slots)
        struct Run { var start: Int; var role: DockIslandRole; var slots: [DockRenderSlot] }
        var runs: [Run] = []
        for (index, slot) in slots.enumerated() {
            let role = roles[index]
            if let last = runs.indices.last, runs[last].role == role {
                runs[last].slots.append(slot)
            } else {
                runs.append(Run(start: index, role: role, slots: [slot]))
            }
        }
        return runs.map { run in
            let meaningful = run.slots.filter { if case .gap = $0 { return false }; if case .group = $0 { return false }; return true }
            let title: DockIslandTitle = meaningful.count == 1 && meaningful[0].target == .launcher
                ? .launcher : .role(run.role)
            return DockIslandBreak(start: run.start, title: title)
        }
    }

    private static func customBreaks(in slots: [DockRenderSlot], islands: [DockIsland]) -> [DockIslandBreak] {
        let explicit = explicitIndex(in: islands)
        let keys = gapKeys(in: slots, islands: islands, explicit: explicit)
        var breaks: [DockIslandBreak] = []
        var currentKey: String?
        for index in slots.indices {
            let key = keys[index].key
            guard key != currentKey else { continue }
            breaks.append(DockIslandBreak(start: breaks.isEmpty ? 0 : index, title: keys[index].title))
            currentKey = key
        }
        return breaks
    }

    /// A drag hole takes the section of the tile it opens, so the gap stays inside that glass.
    /// A hole at the end, with nothing after it, stays with the section it follows.
    private static func gapRoles(in slots: [DockRenderSlot]) -> [DockIslandRole] {
        var roles: [DockIslandRole?] = Array(repeating: nil, count: slots.count)
        var upcoming: DockIslandRole?
        for index in slots.indices.reversed() {
            if case .gap = slots[index] {
                roles[index] = upcoming
            } else {
                let role = role(of: slots[index])
                roles[index] = role
                upcoming = role
            }
        }
        var carried = DockIslandRole.extras
        for index in slots.indices {
            if let role = roles[index] {
                carried = role
            } else {
                roles[index] = carried
            }
        }
        return roles.map { $0 ?? .extras }
    }

    private static func gapKeys(in slots: [DockRenderSlot], islands: [DockIsland],
                                explicit: [String: Int]) -> [(key: String, title: DockIslandTitle)] {
        var assigned: [(key: String, title: DockIslandTitle)?] = Array(repeating: nil, count: slots.count)
        var upcoming: (key: String, title: DockIslandTitle)?
        for index in slots.indices.reversed() {
            if case .gap = slots[index] {
                assigned[index] = upcoming
            } else if let islandIndex = islandIndex(of: slots[index], islands: islands, explicit: explicit) {
                upcoming = (islands[islandIndex].id, storedTitle(islands[islandIndex]))
                assigned[index] = upcoming
            } else {
                let role = role(of: slots[index])
                upcoming = ("leftover:\(role.rawValue)", .role(role))
                assigned[index] = upcoming
            }
        }
        var carried: (key: String, title: DockIslandTitle) = ("gap", .role(.extras))
        for index in slots.indices {
            if let value = assigned[index] {
                carried = value
            } else {
                assigned[index] = carried
            }
        }
        return assigned.map { $0 ?? carried }
    }

    private static func storedTitle(_ island: DockIsland) -> DockIslandTitle {
        let name = island.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return .text(name) }
        if let accepts = island.accepts { return .role(accepts) }
        return .text("")
    }

    private static func explicitIndex(in islands: [DockIsland]) -> [String: Int] {
        var result: [String: Int] = [:]
        for (index, island) in islands.enumerated() {
            for id in island.memberIDs where result[id] == nil { result[id] = index }
        }
        return result
    }

    private static func islandIndex(of slot: DockRenderSlot, islands: [DockIsland], explicit: [String: Int]) -> Int? {
        if case .gap = slot { return nil }
        return islandIndex(id: slot.id, role: role(of: slot), islands: islands, explicit: explicit)
    }

    private static func islandIndex(of snapshot: DockIslandSlotSnapshot, islands: [DockIsland], explicit: [String: Int]) -> Int? {
        islandIndex(id: snapshot.id, role: snapshot.role, islands: islands, explicit: explicit)
    }

    private static func islandIndex(id: String, role: DockIslandRole, islands: [DockIsland], explicit: [String: Int]) -> Int? {
        if let index = explicit[id] { return index }
        return islands.firstIndex { $0.accepts == role }
    }
}
