import AppKit
import Testing

@MainActor
struct DockDragTests {
    private let a = DisplayFixtures.app("a")
    private let b = DisplayFixtures.app("b")
    private let c = DisplayFixtures.app("c")

    @Test("Reordering interprets boundaries before removing the original pin")
    func reorder() {
        #expect(DockPinEditing.inserting([a], into: [a, b, c], at: 3) == [b, c, a])
        #expect(DockPinEditing.inserting([c], into: [a, b, c], at: 0) == [c, a, b])
        #expect(DockPinEditing.inserting([b], into: [a, b, c], at: 2) == [a, b, c])
        #expect(DockPinEditing.moving(a.id, in: [a, b], by: -1) == [a, b])
        #expect(DockPinEditing.moving(b.id, in: [a, b], by: 1) == [a, b])
        #expect(DockPinEditing.moving(b.id, in: [a, b], by: -1) == [b, a])
    }

    @Test("Finder batches insert existing and new apps as one ordered, deduplicated block")
    func batch() {
        #expect(DockPinEditing.inserting([c, a, c], into: [a, b], at: 2) == [b, c, a])
        #expect(DockPinEditing.inserting([b, a, b], into: [], at: 0) == [b, a])
        var bookmarked = a; bookmarked.bookmarkData = Data([1, 2, 3])
        #expect(DockPinEditing.inserting([a], into: [bookmarked, b], at: 2) == [b, bookmarked])
    }

    @Test("Only explicit outside release may unpin", arguments: [false, true])
    func removal(released: Bool) {
        let rect = CGRect(x: -1400, y: -180, width: 400, height: 80)
        let near = CGPoint(x: rect.minX - 63, y: rect.midY)
        let far = CGPoint(x: rect.minX - 64, y: rect.midY)
        var completion = DockDragCompletion(released: released)
        #expect(!completion.shouldUnpin(isPinned: true, distance: DockDragGeometry.distance(near, outside: rect), overDock: false))
        #expect(completion.shouldUnpin(isPinned: true, distance: DockDragGeometry.distance(far, outside: rect), overDock: false) == released)
        #expect(!completion.shouldUnpin(isPinned: true, distance: 100, overDock: true))
        #expect(!completion.shouldUnpin(isPinned: false, distance: 100, overDock: false))
        completion.cancelled = true
        #expect(!completion.shouldUnpin(isPinned: true, distance: 100, overDock: false))
        completion.cancelled = false; completion.committed = true
        #expect(!completion.shouldUnpin(isPinned: true, distance: 100, overDock: false))
    }

    @Test("Insertion uses resting canvas coordinates and accounts for horizontal scrolling")
    func geometry() {
        let layout = DockGeometry.layout(count: 30, favoriteCount: 25, availableLength: 600)
        let point = CGPoint(x: layout.restingCenters[10] + 1 - 150, y: 100)
        #expect(DockDragGeometry.insertion(point: point, scrollOffset: -150, layout: layout, pinCount: 25) == 11)
        #expect(DockDragGeometry.insertion(point: CGPoint(x: layout.restingCenters[27], y: 100), scrollOffset: 0, layout: layout, pinCount: 25) == nil)
        #expect(DockDragGeometry.insertion(point: .zero, scrollOffset: 0, layout: layout, pinCount: 0) == 0)
        #expect(DockDragGeometry.scrollVelocity(position: 0, length: 500) < 0)
        #expect(DockDragGeometry.scrollVelocity(position: 500, length: 500) > 0)
        #expect(DockDragGeometry.scrollVelocity(position: 250, length: 500) == 0)
    }

    @Test("Insertion gaps are transient and retain surviving application identities")
    func preview() {
        let icon = NSImage(size: CGSize(width: 48, height: 48))
        let items = [a, b].map { DockItem(reference: $0, icon: icon, isFavorite: true, isRunning: false, isAvailable: true) }
        let slots = DockRenderSlot.slots(items: items, proposal: DockDragProposal(references: [a, c], index: 2))
        #expect(slots.map(\.id) == ["app:b", "gap:a", "gap:c"])
        #expect(items.map(\.id) == ["a", "b"])
        #expect(DockRenderSlot.slots(items: items, proposal: nil).map(\.id) == ["app:a", "app:b"])
    }

    @Test("Copying between any edges preserves source pins and keeps running apps after unpinning", arguments: DockEdge.allCases, DockEdge.allCases)
    func stores(sourceEdge: DockEdge, destinationEdge: DockEdge) {
        let profiles = DisplayProfilesStore(defaults: DockSettingsStore(repository: nil), repository: nil)
        let displays = [DisplayFixtures.screen("one", runtimeID: 1, primary: true), DisplayFixtures.screen("two", runtimeID: 2)]
        profiles.synchronize(displays) { [a, b] }
        profiles.update(displays[0].id, keyPath: \.edge, to: sourceEdge)
        profiles.update(displays[1].id, keyPath: \.edge, to: destinationEdge)
        let service = DragFixtureService(running: [a])
        let catalog = ApplicationCatalog(service: service)
        catalog.refresh()
        let first = DockStore(displayID: displays[0].id, catalog: catalog, profiles: profiles)
        let second = DockStore(displayID: displays[1].id, catalog: catalog, profiles: profiles)
        let settings = profiles.effectiveSettings(for: displays[1].id)
        let layout = DockGeometry.layout(count: 2, favoriteCount: 2, availableLength: 800, settings: settings)
        let point = destinationEdge.point(CGPoint(x: layout.restingCenters[1] + 1, y: layout.panelDepth - 20), depth: layout.panelDepth)
        let index = DockDragGeometry.insertion(point: point, scrollOffset: 0, layout: layout, pinCount: 2)
        #expect(index == 2)
        #expect(second.insertPins([a], at: index ?? 0))
        first.selectedID = a.id
        profiles.update(displays[0].id, keyPath: \.edge, to: destinationEdge)
        first.refresh()
        #expect(first.selectedID == a.id)
        #expect(first.pins == [a, b])
        #expect(second.pins == [b, a])
        #expect(first.removePin(a.id))
        first.refresh()
        #expect(first.items.map(\.id) == [b.id, a.id])
        #expect(first.items.last?.isFavorite == false)
        #expect(first.items.last?.isRunning == true)
    }

    @Test("Older pins decode without bookmarks; new bookmarks round-trip without changing identity")
    func bookmarks() throws {
        let old = Data(#"{"bundleIdentifier":"a","url":"file:///Fixtures/a.app","name":"a"}"#.utf8)
        let decoded = try JSONDecoder().decode(ApplicationReference.self, from: old)
        #expect(decoded.bookmarkData == nil)
        var updated = decoded; updated.bookmarkData = Data([10, 20, 30])
        let roundTrip = try JSONDecoder().decode(ApplicationReference.self, from: JSONEncoder().encode(updated))
        #expect(roundTrip == updated)
        #expect(roundTrip.id == decoded.id)
    }

    @Test("Corrupt pins refuse a completed edit and preserve the original bytes")
    func blockedWrite() throws {
        let suite = "DeeDockDragTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = DisplayProfilesRepository(defaults: defaults)
        let display = DisplayFixtures.screen("one", runtimeID: 1, primary: true)
        let profiles = DisplayProfilesStore(defaults: DockSettingsStore(repository: nil), repository: repository)
        profiles.synchronize([display]) { [a] }
        // Corrupt every saved pin collection but leave display metadata and migration markers intact.
        let pinKey = "dock.favorites.v2.\(display.id)"
        let corrupt = Data([0xff, 0x00])
        defaults.set(corrupt, forKey: pinKey)
        let reloaded = DisplayProfilesStore(defaults: DockSettingsStore(repository: nil), repository: repository)
        reloaded.synchronize([display]) { [a] }
        let dock = DockStore(displayID: display.id, catalog: ApplicationCatalog(service: DragFixtureService(running: [])), profiles: reloaded)
        #expect(!dock.canEditPins)
        #expect(!dock.insertPins([b], at: 0))
        #expect(dock.errorMessage != nil)
        #expect(defaults.data(forKey: pinKey) == corrupt)
    }

    @Test("Cancelled imports and replaced sessions refuse late completion")
    func staleCompletion() {
        var session = DockSession()
        let original = session.token
        #expect(session.accepts(original))
        session.stop()
        #expect(!session.accepts(original))
        session = DockSession()
        #expect(!session.accepts(original))
        #expect(session.accepts(session.token))
    }

    @Test("Drag visibility holds can be released without a stale delayed hide")
    func visibilityHold() {
        var settings = DockBehaviorSettings(); settings.autoHide = true
        var visibility = DockVisibilityState(settings: settings, reduceMotion: true)
        visibility.showImmediately()
        visibility.update(activation: false, retained: false, held: true, now: 0)
        visibility.advance(now: 10)
        #expect(visibility.progress(at: 10) == 0)
        visibility.update(activation: false, retained: false, held: false, now: 10)
        visibility.stop()
        #expect(visibility.nextUpdate(after: 20) == nil)
        #expect(visibility.progress(at: 20) == 1)
    }
}

@MainActor
private final class DragFixtureService: ApplicationServicing {
    let running: [ApplicationReference]
    init(running: [ApplicationReference]) { self.running = running }
    func runningApplications() -> [ApplicationReference] { running }
    func defaultFavorites() -> [ApplicationReference] { [] }
    func resolvedURL(for reference: ApplicationReference) -> URL? { reference.url }
    func icon(for url: URL?) -> NSImage { NSImage(size: CGSize(width: 48, height: 48)) }
    func pruneIcons(keeping urls: Set<URL>) {}
    func open(_ reference: ApplicationReference) async throws { Issue.record("Drag tests must never launch applications") }
}
