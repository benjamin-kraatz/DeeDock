import AppKit
import Foundation
import Testing
@testable import DeeDock

/// Island plans, their reconciliation with pin edits, slot grouping, and island geometry.
@MainActor
struct DockIslandTests {
    private func app(_ id: String, pinned: Bool, running: Bool = true) -> DockRenderSlot {
        .app(DockItem(reference: DisplayFixtures.app(id), icon: NSImage(size: CGSize(width: 48, height: 48)),
                      isFavorite: pinned, isRunning: running, isAvailable: true))
    }

    private var trash: DockRenderSlot {
        .trash(TrashDockItem(state: .empty, icon: NSImage(size: CGSize(width: 48, height: 48))))
    }

    // MARK: Plan

    @Test("An empty plan reconciles to one pinned island covering every pin")
    func automaticPlan() {
        let plan = DockIslandPlan.automatic.reconciled(pinCount: 4)
        #expect(plan.pinnedIslands.map(\.pinCount) == [4])
        #expect(plan.pinnedIslands.first?.kind == .pinned)
        #expect(plan.isAutomatic)
        #expect(DockIslandPlan.automatic.reconciled(pinCount: 0).pinnedIslands.map(\.pinCount) == [0])
    }

    @Test("Reconciling trims from the end, extends the last island, and drops emptied islands but the first")
    func reconcile() {
        let plan = DockIslandPlan(pinnedIslands: [DockIsland(kind: .pinned, pinCount: 2),
                                                  DockIsland(kind: .custom, pinCount: 3),
                                                  DockIsland(kind: .custom, pinCount: 1)])
        #expect(plan.reconciled(pinCount: 8).pinnedIslands.map(\.pinCount) == [2, 3, 3])
        #expect(plan.reconciled(pinCount: 4).pinnedIslands.map(\.pinCount) == [2, 2])
        #expect(plan.reconciled(pinCount: 0).pinnedIslands.map(\.pinCount) == [0])
        #expect(plan.reconciled(pinCount: 0).pinnedIslands.first?.id == plan.pinnedIslands[0].id)
    }

    @Test("Splitting at a pin opens a custom island; splitting at an island start changes nothing")
    func split() {
        let split = DockIslandPlan.automatic.splitting(beforePin: 2, pinCount: 5)
        #expect(split.pinnedIslands.map(\.pinCount) == [2, 3])
        #expect(split.pinnedIslands.map(\.kind) == [.pinned, .custom])
        #expect(split.pinnedIslandStarts(pinCount: 5) == [0, 2])
        #expect(split.splitting(beforePin: 2, pinCount: 5) == split)
        #expect(split.splitting(beforePin: 0, pinCount: 5) == split)
        #expect(split.pinnedIslandIndex(forPin: 4, pinCount: 5) == 1)
    }

    @Test("Merging folds an island into its neighbour, which keeps its identity and name")
    func merge() {
        let plan = DockIslandPlan(pinnedIslands: [DockIsland(kind: .pinned, pinCount: 2),
                                                  DockIsland(kind: .custom, name: "Chat", tint: .pink, pinCount: 2),
                                                  DockIsland(kind: .custom, pinCount: 1)])
        let left = plan.merging(islandAt: 1, into: -1, pinCount: 5)
        #expect(left.pinnedIslands.map(\.pinCount) == [4, 1])
        #expect(left.pinnedIslands[0].id == plan.pinnedIslands[0].id)
        let right = plan.merging(islandAt: 1, into: 1, pinCount: 5)
        #expect(right.pinnedIslands.map(\.pinCount) == [2, 3])
        #expect(right.pinnedIslands[1].id == plan.pinnedIslands[2].id)
        // Merging the pinned island away promotes the survivor so one island always holds that kind.
        let gone = plan.merging(islandAt: 0, into: 1, pinCount: 5)
        #expect(gone.pinnedIslands.map(\.kind) == [.pinned, .custom])
        #expect(gone.pinnedIslands[0].name == "Chat")
        #expect(plan.merging(islandAt: 0, into: -1, pinCount: 5) == plan.reconciled(pinCount: 5))
    }

    @Test("Pins follow their island through reorder, insertion, and removal")
    func following() {
        let plan = DockIslandPlan(pinnedIslands: [DockIsland(kind: .pinned, pinCount: 2),
                                                  DockIsland(kind: .custom, pinCount: 2)])
        let previous = ["a", "b", "c", "d"]
        // A new pin joins the island of the pin before it.
        #expect(plan.following(previous: previous, next: ["a", "b", "x", "c", "d"], relocated: ["x"]).pinnedIslands.map(\.pinCount) == [3, 2])
        // Inserted first, it joins the island of the pin after it.
        #expect(plan.following(previous: previous, next: ["x", "a", "b", "c", "d"], relocated: ["x"]).pinnedIslands.map(\.pinCount) == [3, 2])
        // Appended, it joins the last island.
        #expect(plan.following(previous: previous, next: previous + ["x"], relocated: ["x"]).pinnedIslands.map(\.pinCount) == [2, 3])
        // A moved pin changes island; the one it left keeps the rest.
        #expect(plan.following(previous: previous, next: ["b", "c", "a", "d"], relocated: ["a"]).pinnedIslands.map(\.pinCount) == [1, 3])
        // Removing both pins of the second island drops it.
        #expect(plan.following(previous: previous, next: ["a", "b"]).pinnedIslands.map(\.pinCount) == [2])
        // Removing both pins of the first island keeps its identity at zero.
        let emptiedFirst = plan.following(previous: previous, next: ["c", "d"])
        #expect(emptiedFirst.pinnedIslands.map(\.pinCount) == [0, 2])
        #expect(emptiedFirst.pinnedIslands[0].id == plan.pinnedIslands[0].id)
    }

    @Test("Renaming and tinting touch only the named island, and kind islands materialise on first edit")
    func naming() {
        let plan = DockIslandPlan.automatic.reconciled(pinCount: 1)
        let island = plan.pinnedIslands[0]
        #expect(plan.renaming(island.id, to: "  Work ").pinnedIslands[0].name == "Work")
        #expect(plan.renaming(island.id, to: "Work").renaming(island.id, to: "  ").pinnedIslands[0].name == nil)
        #expect(plan.tinting(island.id, .gold).pinnedIslands[0].tint == .gold)
        let running = plan.updating(kind: .running) { $0.name = "Open" }
        #expect(running.island(for: .running).name == "Open")
        #expect(running.kindIslands.count == 1)
        #expect(running.updating(kind: .running) { $0.tint = .teal }.kindIslands.count == 1)
        #expect(!running.isAutomatic)
        #expect(plan.updating(kind: .pinned) { $0.name = "no" } == plan)
    }

    @Test("Plans round-trip through JSON and tolerate missing optional keys")
    func codable() throws {
        let plan = DockIslandPlan(pinnedIslands: [DockIsland(kind: .pinned, pinCount: 2),
                                                  DockIsland(kind: .custom, name: "Chat", tint: .pink, pinCount: 1)],
                                  kindIslands: [DockIsland(kind: .running, tint: .green)])
        let data = try JSONEncoder().encode(plan)
        #expect(try JSONDecoder().decode(DockIslandPlan.self, from: data) == plan)
        let minimal = try JSONDecoder().decode(DockIslandPlan.self, from: Data("{}".utf8))
        #expect(minimal == .automatic)
        let island = try JSONDecoder().decode(DockIsland.self, from: Data(#"{"id":"\#(UUID().uuidString)","kind":"custom"}"#.utf8))
        #expect(island.tint == .automatic && island.pinCount == 0)
    }

    @Test("The repository removes the key for an automatic plan and reports corrupt data")
    func repository() throws {
        let defaults = try #require(UserDefaults(suiteName: "DockIslandTests.\(UUID().uuidString)"))
        let repository = DockIslandPlanRepository(defaults: defaults, displayID: "d")
        #expect(try repository.load() == nil)
        let plan = DockIslandPlan(pinnedIslands: [DockIsland(kind: .pinned, pinCount: 1), DockIsland(kind: .custom, pinCount: 1)])
        try repository.save(plan)
        #expect(try repository.load() == plan)
        try repository.save(.automatic)
        #expect(defaults.object(forKey: "dock.islands.v1.d") == nil)
        defaults.set("junk", forKey: "dock.islands.v1.d")
        #expect(throws: (any Error).self) { try repository.load() }
    }

    @Test("Island settings decode missing keys to defaults and nest inside DockSettings")
    func settings() throws {
        let decoded = try JSONDecoder().decode(DockIslandSettings.self, from: Data(#"{"isEnabled":true}"#.utf8))
        #expect(decoded.isEnabled && decoded.style == .ice && decoded.gap == 12 && decoded.rim == 4.5)
        var settings = DockSettings.defaults
        settings.islands.isEnabled = true
        settings.islands.glow = 1.337
        let data = try JSONEncoder().encode(settings)
        let round = try JSONDecoder().decode(DockSettings.self, from: data)
        #expect(round.islands.isEnabled)
        #expect(round.normalized?.islands.glow == 1.35)
        settings.islands.gap = 100
        #expect(!settings.isValid)
        // An override document without the key inherits the shared value.
        #expect(DockSettingsOverrides().resolving(round).islands == round.islands)
        // A complete document saved before islands existed decodes with islands off.
        var document = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(DockSettings.defaults)) as? [String: Any])
        document.removeValue(forKey: "islands")
        let older = try JSONDecoder().decode(DockSettings.self, from: try JSONSerialization.data(withJSONObject: document))
        #expect(older.islands == DockIslandSettings.defaults)
        #expect(!older.islands.isEnabled)
    }

    // MARK: Assignment

    @Test("Slots group into tile, pinned, running, and utilities islands in dock order")
    func spans() {
        let slots: [DockRenderSlot] = [.launcher, app("a", pinned: true), app("b", pinned: true), app("c", pinned: false), trash]
        let spans = DockIslandAssignment.spans(slots: slots, plan: .automatic, pinOrder: ["a", "b"])
        #expect(spans.map(\.island.kind) == [.tile, .pinned, .running, .utilities])
        #expect(spans.map(\.range) == [0..<1, 1..<3, 3..<4, 4..<5])
        #expect(DockIslandAssignment.spans(slots: [], plan: .automatic, pinOrder: []).isEmpty)
    }

    @Test("Split pins form separate islands, gaps join the open island, and the tile among pins splits the run")
    func pinnedSpans() {
        let plan = DockIslandPlan(pinnedIslands: [DockIsland(kind: .pinned, pinCount: 1), DockIsland(kind: .custom, pinCount: 2)])
        let slots: [DockRenderSlot] = [app("a", pinned: true), .gap("x"), app("b", pinned: true), app("c", pinned: true)]
        let order = ["a", "b", "c"]
        let spans = DockIslandAssignment.spans(slots: slots, plan: plan, pinOrder: order)
        #expect(spans.map(\.range) == [0..<2, 2..<4])
        #expect(spans.map(\.customIndex) == [0, 0])
        let launcherAmong: [DockRenderSlot] = [app("a", pinned: true), .launcher, app("b", pinned: true), app("c", pinned: true)]
        let around = DockIslandAssignment.spans(slots: launcherAmong, plan: .automatic, pinOrder: order)
        #expect(around.map(\.island.kind) == [.pinned, .tile, .pinned])
        #expect(around[0].island.id == around[2].island.id)
        #expect(Set(around.map(\.id)).count == 3)
        // A custom island split by the tile keeps one palette index on both sides.
        let customAround = DockIslandAssignment.spans(slots: launcherAmong, plan: plan, pinOrder: order)
        #expect(customAround.map(\.customIndex) == [0, 0, 0])
        let twoCustom = DockIslandPlan(pinnedIslands: [DockIsland(kind: .pinned, pinCount: 1), DockIsland(kind: .custom, pinCount: 1),
                                                       DockIsland(kind: .custom, pinCount: 1)])
        let three: [DockRenderSlot] = [app("a", pinned: true), app("b", pinned: true), app("c", pinned: true)]
        #expect(DockIslandAssignment.spans(slots: three, plan: twoCustom, pinOrder: order).map(\.customIndex) == [0, 0, 1])
        // Hiding the first custom island leaves the second its colour.
        #expect(DockIslandAssignment.spans(slots: [app("a", pinned: true), app("c", pinned: true)], plan: twoCustom, pinOrder: order)
            .map(\.customIndex) == [0, 1])
        let collapsed: [DockRenderSlot] = [.group(DockGroupControl(group: .pinned, count: 3, expanded: false)), app("c", pinned: false)]
        #expect(DockIslandAssignment.spans(slots: collapsed, plan: plan, pinOrder: order).map(\.island.kind) == [.pinned, .running])
    }

    @Test("A pin parked off the dock or lifted into a drag leaves the others in their islands")
    func filteredPins() {
        let plan = DockIslandPlan(pinnedIslands: [DockIsland(kind: .pinned, pinCount: 2), DockIsland(kind: .custom, pinCount: 2)])
        let order = ["a", "b", "c", "d"]
        // "a" parked on a magnetic edge: b stays red, c and d stay blue.
        let hidden: [DockRenderSlot] = [app("b", pinned: true), app("c", pinned: true), app("d", pinned: true)]
        let spans = DockIslandAssignment.spans(slots: hidden, plan: plan, pinOrder: order)
        #expect(spans.map(\.range) == [0..<1, 1..<3])
        #expect(spans.map(\.island.id) == plan.pinnedIslands.map(\.id))
        // "a" dragged between c and d: its gap previews inside the island it hovers.
        let dragged: [DockRenderSlot] = [app("b", pinned: true), app("c", pinned: true), .gap("a"), app("d", pinned: true)]
        #expect(DockIslandAssignment.spans(slots: dragged, plan: plan, pinOrder: order).map(\.range) == [0..<1, 1..<4])
        // A pin the saved list does not know counts after the known ones.
        let extra: [DockRenderSlot] = [app("a", pinned: true), app("x", pinned: true)]
        #expect(DockIslandAssignment.spans(slots: extra, plan: .automatic, pinOrder: ["a"]).map(\.range) == [0..<2])
    }

    @Test("Automatic islands keep one identity, so the first rename or tint lands")
    func stableAutomaticIdentity() {
        let first = DockIslandPlan.automatic.reconciled(pinCount: 3)
        let second = DockIslandPlan.automatic.reconciled(pinCount: 3)
        #expect(first.pinnedIslands[0].id == second.pinnedIslands[0].id)
        #expect(first.island(for: .running).id == second.island(for: .running).id)
        let tinted = second.tinting(first.pinnedIslands[0].id, .gold)
        #expect(tinted.pinnedIslands.first?.tint == .gold)
        #expect(DockIslandPlan.automatic.tinting(DockIsland.automaticID(for: .pinned), .teal).pinnedIslands.first?.tint == .teal)
        let running = DockIslandPlan.automatic.renaming(DockIsland.automaticID(for: .running), to: "Open")
        #expect(running.island(for: .running).name == "Open")
        #expect(running.island(for: .running).id == DockIsland.automaticID(for: .running))
    }

    // MARK: Geometry

    @Test("Island layout replaces dividers, pads each island, and reports one frame per island")
    func geometry() {
        let islands = DockGeometry.IslandLayout(starts: [0, 2, 3], gap: 12, padding: 10)
        let layout = DockGeometry.layout(count: 4, favoriteCount: 2, utilityCount: 1, availableLength: 1400, islands: islands)
        #expect(layout.separatorIndices.isEmpty)
        #expect(layout.alongInset == 10 && layout.crossInset == 10)
        #expect(layout.surfaceDepth == 48 + DockGeometry.indicatorAreaDepth + 20)
        let sizes = Array(repeating: layout.iconSize, count: 4)
        let frames = layout.islandFrames(sizes: sizes)
        #expect(frames.count == 3)
        #expect(frames[0].width == 2 * 48 + 4 + 20)
        #expect(abs(frames[1].minX - frames[0].maxX - 12) < 0.001)
        #expect(abs(frames[2].minX - frames[1].maxX - 12) < 0.001)
        let union = layout.surfaceFrame(sizes: sizes)
        #expect(abs(union.minX - frames[0].minX) < 0.001 && abs(union.maxX - frames[2].maxX) < 0.001)
        #expect(union.height == layout.surfaceDepth)
        let plain = DockGeometry.layout(count: 4, favoriteCount: 2, utilityCount: 1, availableLength: 1400)
        #expect(plain.islandFrames(sizes: sizes) == [plain.surfaceFrame(sizes: sizes)])
        #expect(plain.separatorIndices == [2, 3])
    }

    @Test("Magnification stretches an island along the dock but never across it")
    func magnifiedIslands() {
        let islands = DockGeometry.IslandLayout(starts: [0, 2], gap: 12, padding: 10)
        let layout = DockGeometry.layout(count: 4, favoriteCount: 4, availableLength: 1400, islands: islands)
        let resting = layout.islandFrames(sizes: layout.sizes(pointerAlong: nil, reduceMotion: false))
        let hovered = layout.islandFrames(sizes: layout.sizes(pointerAlong: layout.restingCenters[0], reduceMotion: false))
        #expect(hovered[0].width > resting[0].width)
        #expect(hovered[0].height == resting[0].height)
        #expect(abs(hovered[1].minX - hovered[0].maxX - 12) < 0.001)
    }

    @Test("Icon sampling finds a saturated hue and blends mixed islands toward neutral")
    func sampler() {
        let blue = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor(calibratedRed: 0.1, green: 0.3, blue: 0.95, alpha: 1).setFill(); rect.fill(); return true
        }
        let color = DockIconTintSampler.color(of: blue)
        #expect(color.map { (200...250).contains($0.hue) } == true)
        let grey = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor(white: 0.5, alpha: 1).setFill(); rect.fill(); return true
        }
        #expect(DockIconTintSampler.color(of: grey) == nil)
        let opposite = DockIconTintSampler.blend([DockIslandColor(hue: 0, saturation: 1), DockIslandColor(hue: 180, saturation: 1)])
        #expect(opposite == nil)
        let agreeing = DockIconTintSampler.blend([DockIslandColor(hue: 40, saturation: 1), DockIslandColor(hue: 50, saturation: 1)])
        #expect(agreeing.map { (40...50).contains($0.hue) && $0.saturation > 0.8 } == true)
    }
}
