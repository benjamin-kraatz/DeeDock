import Foundation

/// What an island holds. The dock generates one island per kind; pinned tiles can be split into
/// several `pinned` and `custom` islands by the user.
enum DockIslandKind: String, Codable, CaseIterable, Sendable {
    /// The DOKK tile, always alone.
    case tile
    /// The first run of pinned apps and folders. Only one island has this kind.
    case pinned
    /// A further run of pinned tiles the user split off.
    case custom
    /// Running apps that are not pinned, including the collapsed Running control.
    case running
    /// Downloads, the Shelf, capsules, feeds, drives, Trash, and every other trailing tile.
    case utilities

    /// Whether this kind holds a run of pinned tiles and so carries a `pinCount`.
    var holdsPins: Bool { self == .pinned || self == .custom }

    /// The island's name until the user renames it.
    var defaultName: LocalizedStringResource {
        switch self {
        case .tile: .islandsNameTile
        case .pinned: .islandsNamePinned
        case .custom: .islandsNameCustom
        case .running: .islandsNameRunning
        case .utilities: .islandsNameUtilities
        }
    }
}

/// A per-island colour choice. `automatic` follows the dock-wide tint mode.
enum DockIslandTint: String, Codable, CaseIterable, Sendable {
    case automatic, blue, purple, gold, teal, graphite, pink, green, orange, none

    var title: LocalizedStringResource {
        switch self {
        case .automatic: .islandsTintAutomatic
        case .blue: .islandsTintBlue
        case .purple: .islandsTintPurple
        case .gold: .islandsTintGold
        case .teal: .islandsTintTeal
        case .graphite: .islandsTintGraphite
        case .pink: .islandsTintPink
        case .green: .islandsTintGreen
        case .orange: .islandsTintOrange
        case .none: .islandsTintNone
        }
    }
}

/// One island of a dock: its identity, kind, user naming and tint, and for pinned islands the
/// number of consecutive pins it holds.
///
/// Pin order stays authoritative in the pin list. An island never lists pin IDs; it only says how
/// many of the next pins belong to it, so a reorder, insert, or removal is reconciled by counts
/// (see ``DockIslandPlan/following(previous:next:relocated:)``) and never leaves a pin orphaned.
struct DockIsland: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id = UUID()
    var kind: DockIslandKind
    /// The user's name, or nil for the kind's default. Never sent to analytics.
    var name: String?
    var tint: DockIslandTint = .automatic
    /// Consecutive pins in this island, in pin order. Zero for every kind that does not hold pins.
    var pinCount = 0

    init(id: UUID = UUID(), kind: DockIslandKind, name: String? = nil, tint: DockIslandTint = .automatic, pinCount: Int = 0) {
        self.id = id
        self.kind = kind
        self.name = name
        self.tint = tint
        self.pinCount = kind.holdsPins ? max(0, pinCount) : 0
    }

    private enum CodingKeys: String, CodingKey { case id, kind, name, tint, pinCount }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try values.decode(DockIslandKind.self, forKey: .kind)
        self.init(id: try values.decode(UUID.self, forKey: .id), kind: kind,
                  name: try values.decodeIfPresent(String.self, forKey: .name),
                  tint: try values.decodeIfPresent(DockIslandTint.self, forKey: .tint) ?? .automatic,
                  pinCount: try values.decodeIfPresent(Int.self, forKey: .pinCount) ?? 0)
    }

    /// The name shown in menus, Settings, and accessibility labels.
    var displayName: String {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        return String(localized: kind.defaultName)
    }
}

/// One display's island arrangement: how its pins are split into islands, plus any naming or
/// tint the user gave the automatic islands.
///
/// An empty plan is the automatic arrangement: one island per kind present in the dock. The plan
/// stores no pin IDs, app names, or anything else that identifies an app.
struct DockIslandPlan: Codable, Equatable, Sendable {
    /// Islands holding pins, in pin order. Empty means one automatic pinned island.
    var pinnedIslands: [DockIsland] = []
    /// User customisation of the tile, running, and utilities islands, at most one per kind.
    var kindIslands: [DockIsland] = []

    static let automatic = DockIslandPlan()

    init(pinnedIslands: [DockIsland] = [], kindIslands: [DockIsland] = []) {
        self.pinnedIslands = pinnedIslands.filter { $0.kind.holdsPins }
        self.kindIslands = kindIslands.filter { !$0.kind.holdsPins }
    }

    private enum CodingKeys: String, CodingKey { case pinnedIslands, kindIslands }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(pinnedIslands: try values.decodeIfPresent([DockIsland].self, forKey: .pinnedIslands) ?? [],
                  kindIslands: try values.decodeIfPresent([DockIsland].self, forKey: .kindIslands) ?? [])
    }

    /// True when nothing differs from the automatic arrangement.
    var isAutomatic: Bool {
        kindIslands.isEmpty && pinnedIslands.allSatisfy { $0.kind == .pinned && $0.name == nil && $0.tint == .automatic }
            && pinnedIslands.count <= 1
    }

    /// The island drawn for a kind that holds no pins.
    func island(for kind: DockIslandKind) -> DockIsland {
        kindIslands.first { $0.kind == kind } ?? DockIsland(kind: kind)
    }

    /// Every island in the plan, pinned islands first.
    var islands: [DockIsland] { pinnedIslands + kindIslands }

    /// Pinned islands whose counts cover exactly `pinCount` pins.
    ///
    /// Counts never line up after a Dock Mode switch or an edit on another display, so every
    /// read-side consumer goes through this. Surplus pins join the last island; missing pins shrink
    /// islands from the end. An island left with no pins is dropped, except that the first island
    /// survives at zero so its name and tint outlive an empty pin list.
    func reconciled(pinCount: Int) -> DockIslandPlan {
        let pinCount = max(0, pinCount)
        var islands = pinnedIslands.isEmpty ? [DockIsland(kind: .pinned)] : pinnedIslands
        var remaining = pinCount
        for index in islands.indices {
            let count = min(islands[index].pinCount, remaining)
            islands[index].pinCount = count
            remaining -= count
        }
        islands[islands.count - 1].pinCount += remaining
        let kept = islands.enumerated().filter { $0.offset == 0 || $0.element.pinCount > 0 }.map(\.element)
        return DockIslandPlan(pinnedIslands: kept, kindIslands: kindIslands)
    }

    /// Index of the pinned island holding the pin at `pinIndex`, after reconciling to `pinCount`.
    func pinnedIslandIndex(forPin pinIndex: Int, pinCount: Int) -> Int? {
        let islands = reconciled(pinCount: pinCount).pinnedIslands
        var start = 0
        for (index, island) in islands.enumerated() {
            if pinIndex < start + island.pinCount { return index }
            start += island.pinCount
        }
        return nil
    }

    /// The first pin index of each pinned island, after reconciling to `pinCount`.
    func pinnedIslandStarts(pinCount: Int) -> [Int] {
        var start = 0
        return reconciled(pinCount: pinCount).pinnedIslands.map { island in
            defer { start += island.pinCount }
            return start
        }
    }

    // MARK: Edits

    /// Starts a new island at `pinIndex`, moving it and the pins after it in the same island into a
    /// new custom island. A pin already at the start of its island leaves the plan unchanged.
    func splitting(beforePin pinIndex: Int, pinCount: Int) -> DockIslandPlan {
        var plan = reconciled(pinCount: pinCount)
        guard let index = plan.pinnedIslandIndex(forPin: pinIndex, pinCount: pinCount) else { return plan }
        let start = plan.pinnedIslandStarts(pinCount: pinCount)[index]
        let offset = pinIndex - start
        guard offset > 0 else { return plan }
        let moved = plan.pinnedIslands[index].pinCount - offset
        plan.pinnedIslands[index].pinCount = offset
        plan.pinnedIslands.insert(DockIsland(kind: .custom, pinCount: moved), at: index + 1)
        return plan
    }

    /// Folds the pinned island at `index` into its neighbour. The neighbour keeps its identity,
    /// name, and tint. Out-of-range neighbours leave the plan unchanged.
    func merging(islandAt index: Int, into direction: Int, pinCount: Int) -> DockIslandPlan {
        var plan = reconciled(pinCount: pinCount)
        let target = index + direction
        guard direction != 0, plan.pinnedIslands.indices.contains(index), plan.pinnedIslands.indices.contains(target) else { return plan }
        plan.pinnedIslands[target].pinCount += plan.pinnedIslands[index].pinCount
        plan.pinnedIslands.remove(at: index)
        if !plan.pinnedIslands.isEmpty && !plan.pinnedIslands.contains(where: { $0.kind == .pinned }) {
            plan.pinnedIslands[0].kind = .pinned
        }
        return plan
    }

    /// Renames any island. Blank names return to the kind's default.
    func renaming(_ id: UUID, to name: String?) -> DockIslandPlan {
        updating(id) { island in
            let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            island.name = trimmed.isEmpty ? nil : trimmed
        }
    }

    func tinting(_ id: UUID, _ tint: DockIslandTint) -> DockIslandPlan {
        updating(id) { $0.tint = tint }
    }

    /// Applies `mutation` to the island with `id`, materialising a kind island the first time it is
    /// customised.
    func updating(_ id: UUID, mutation: (inout DockIsland) -> Void) -> DockIslandPlan {
        var plan = self
        if let index = plan.pinnedIslands.firstIndex(where: { $0.id == id }) {
            mutation(&plan.pinnedIslands[index])
        } else if let index = plan.kindIslands.firstIndex(where: { $0.id == id }) {
            mutation(&plan.kindIslands[index])
        }
        return plan
    }

    /// Customises the island for a kind that holds no pins, creating its entry on first use.
    func updating(kind: DockIslandKind, mutation: (inout DockIsland) -> Void) -> DockIslandPlan {
        guard !kind.holdsPins else { return self }
        var plan = self
        if let index = plan.kindIslands.firstIndex(where: { $0.kind == kind }) {
            mutation(&plan.kindIslands[index])
        } else {
            var island = DockIsland(kind: kind)
            mutation(&island)
            plan.kindIslands.append(island)
        }
        return plan
    }

    /// Carries island membership across a pin edit.
    ///
    /// A pin that existed before and was not `relocated` keeps its island. Every other pin joins
    /// the island of the nearest unmoved pin before it in the new order, then after it, then the
    /// first island. Islands left without pins disappear, except the first.
    /// - Parameters:
    ///   - previous: Pin IDs before the edit.
    ///   - next: Pin IDs after the edit.
    ///   - relocated: Pins the edit moved or inserted.
    func following(previous: [String], next: [String], relocated: Set<String> = []) -> DockIslandPlan {
        let plan = reconciled(pinCount: previous.count)
        let starts = plan.pinnedIslandStarts(pinCount: previous.count)
        func island(ofPrevious index: Int) -> Int {
            starts.lastIndex { $0 <= index } ?? 0
        }
        let anchored: [Int?] = next.enumerated().map { _, id in
            guard !relocated.contains(id), let index = previous.firstIndex(of: id) else { return nil }
            return island(ofPrevious: index)
        }
        var counts = Array(repeating: 0, count: plan.pinnedIslands.count)
        for index in next.indices {
            let before = anchored[..<index].reversed().lazy.compactMap { $0 }.first
            let after = anchored[index...].lazy.compactMap { $0 }.first
            counts[anchored[index] ?? before ?? after ?? 0] += 1
        }
        var islands = plan.pinnedIslands
        for index in islands.indices { islands[index].pinCount = counts[index] }
        let kept = islands.enumerated().filter { $0.offset == 0 || $0.element.pinCount > 0 }.map(\.element)
        return DockIslandPlan(pinnedIslands: kept, kindIslands: kindIslands)
    }
}
