import AppKit
import Foundation
import Testing

@MainActor
struct ShelfTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func file(_ name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("shelf".utf8).write(to: url)
        return url
    }

    private func controller(_ defaults: UserDefaults) -> ShelfController {
        // Sandboxed bookmarks need a user-initiated drop; tests stand in a deterministic token.
        ShelfController(repository: ShelfRepository(defaults: defaults), bookmark: { Data($0.path.utf8) })
    }

    @Test("Staged items survive a save and load round trip")
    func persistence() throws {
        let suite = "ShelfPersistence.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try file("first.txt", in: directory)
        let second = try file("second.txt", in: directory)
        let shelf = controller(defaults)
        shelf.start()
        try shelf.add([first, second])

        let reloaded = controller(defaults)
        reloaded.start()
        #expect(reloaded.items.map(\.name) == shelf.items.map(\.name))
        #expect(reloaded.items.map(\.url) == [first, second].map(\.standardizedFileURL).reversed())
        #expect(reloaded.items.allSatisfy { !$0.bookmarkData.isEmpty })
    }

    @Test("Unreadable storage is reported and never overwritten")
    func corruptData() throws {
        let suite = "ShelfCorrupt.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let bytes = Data("not a shelf".utf8)
        defaults.set(bytes, forKey: "dock.shelf.v1")

        let repository = ShelfRepository(defaults: defaults)
        #expect(throws: (any Error).self) { try repository.load() }
        #expect(defaults.data(forKey: "dock.shelf.v1") == bytes)

        let shelf = controller(defaults)
        shelf.start()
        #expect(shelf.requiresReset)
        #expect(shelf.loadFailure != nil)
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(throws: (any Error).self) { try shelf.add([try self.file("blocked.txt", in: directory)]) }
        #expect(defaults.data(forKey: "dock.shelf.v1") == bytes)

        try shelf.reset()
        #expect(!shelf.requiresReset)
        #expect(defaults.data(forKey: "dock.shelf.v1") != bytes)
    }

    @Test("A document from an unknown version fails rather than reading as an empty Shelf")
    func versionGuard() throws {
        let suite = "ShelfVersion.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let bytes = Data(#"{"version":99,"items":[]}"#.utf8)
        defaults.set(bytes, forKey: "dock.shelf.v1")
        #expect(throws: (any Error).self) { try ShelfRepository(defaults: defaults).load() }
        #expect(defaults.data(forKey: "dock.shelf.v1") == bytes)
    }

    @Test("Staging skips duplicates and reports what did not fit")
    func stagingRules() throws {
        let suite = "ShelfStaging.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let shelf = controller(defaults)
        shelf.start()

        let one = try file("one.txt", in: directory)
        #expect(try shelf.add([one, one]) == 0)
        #expect(shelf.items.count == 1)
        #expect(try shelf.add([one]) == 0)
        #expect(shelf.items.count == 1)

        #expect(try shelf.add([directory.appendingPathComponent("missing.txt")]) == 1)
        #expect(shelf.items.count == 1)

        let extras = try (0..<ShelfDocument.capacity).map { try file("extra\($0).txt", in: directory) }
        let rejected = try shelf.add(extras)
        #expect(shelf.items.count == ShelfDocument.capacity)
        #expect(rejected == extras.count - (ShelfDocument.capacity - 1))
    }

    @Test("Removal is explicit: clearing and per-item removal, never a drag")
    func removal() throws {
        let suite = "ShelfRemoval.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let shelf = controller(defaults)
        shelf.start()
        try shelf.add([try file("a.txt", in: directory), try file("b.txt", in: directory)])

        let first = try #require(shelf.items.first)
        try shelf.remove(ids: [first.id])
        #expect(shelf.items.count == 1)
        #expect(!shelf.items.contains { $0.id == first.id })

        try shelf.clear()
        #expect(shelf.isEmpty)
        let reloaded = controller(defaults)
        reloaded.start()
        #expect(reloaded.isEmpty)
    }

    @Test("Dragging an item out leaves it staged")
    func dragKeepsItems() throws {
        let suite = "ShelfDrag.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let shelf = controller(defaults)
        shelf.start()
        try shelf.add([try file("carried.txt", in: directory)])
        let staged = try #require(shelf.items.first)

        // Resolving is everything a completed drag does to the controller.
        let access = try #require(shelf.resolve(staged.id))
        #expect(access.url == staged.url)
        #expect(shelf.items.map(\.id) == [staged.id])

        let reloaded = controller(defaults)
        reloaded.start()
        #expect(reloaded.items.map(\.id) == [staged.id])
    }

    @Test("A missing file stays listed as unavailable instead of disappearing")
    func unavailableItemsRemain() throws {
        let suite = "ShelfMissing.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let shelf = controller(defaults)
        shelf.start()
        let url = try file("vanishing.txt", in: directory)
        try shelf.add([url])
        let staged = try #require(shelf.items.first)

        try FileManager.default.removeItem(at: url)
        #expect(shelf.items.count == 1)
        #expect(!shelf.isAvailable(staged))
        #expect(shelf.resolve(staged.id) == nil)
    }

    @Test("Security scope is released once, and only when it was acquired")
    func accessLifetime() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try file("scoped.txt", in: directory)
        let item = ShelfItem(url: url, name: "scoped.txt", bookmarkData: Data())

        final class Counter: @unchecked Sendable { var stops = 0 }
        let acquired = Counter()
        do {
            let access = ShelfResourceAccess(item, startAccess: { _ in true },
                                             stopAccess: { _ in acquired.stops += 1 })
            #expect(access.isAvailable)
        }
        #expect(acquired.stops == 1)

        let refused = Counter()
        do {
            _ = ShelfResourceAccess(item, startAccess: { _ in false }, stopAccess: { _ in refused.stops += 1 })
        }
        #expect(refused.stops == 0)
    }

    @Test("Utility tiles trail every application, Shelf first, sharing one divider",
          arguments: DockEdge.allCases)
    func projectionAndDivider(edge: DockEdge) {
        let pinned = DockItem(reference: DisplayFixtures.app("pinned"), icon: NSImage(), isFavorite: true,
                              isRunning: false, isAvailable: true)
        let running = DockItem(reference: DisplayFixtures.app("running"), icon: NSImage(), isFavorite: false,
                               isRunning: true, isAvailable: true)
        let shelf = ShelfDockItem(count: 2, icon: NSImage())
        let trash = TrashDockItem(state: .empty, icon: NSImage())
        let entries = DockSectionProjection.entries(items: [pinned, running], visibility: .showAll,
                                                    expanded: true, shelf: shelf, trash: trash)

        #expect(entries.map(\.target) == [.app("pinned"), .app("running"), .shelf, .trash])
        #expect(entries.filter(\.isUtility).count == 2)

        var settings = DockSettings.defaults
        settings.edge = edge
        let layout = DockGeometry.layout(count: entries.count, favoriteCount: 1, utilityCount: 2,
                                         availableLength: 1600, settings: settings)
        // One divider before the pair, one between pinned and running: never one between the tiles.
        #expect(layout.separatorIndices == [1, 2])
    }

    @Test("A rubber band selects every row it touches, and nothing it misses")
    func bandSelection() {
        let ids = (0..<4).map { _ in UUID() }
        let frames = Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
            (id, CGRect(x: 8, y: CGFloat(index) * 48, width: 400, height: 46))
        })
        // Swept upward from the third row into the second: direction must not matter.
        let band = ShelfSelection.band(from: CGPoint(x: 20, y: 120), to: CGPoint(x: 60, y: 60))
        #expect(band == CGRect(x: 20, y: 60, width: 40, height: 60))
        #expect(ShelfSelection.within(band, frames: frames) == Set([ids[1], ids[2]]))
        #expect(ShelfSelection.within(.zero, frames: frames).isEmpty)
    }

    @Test("Command toggles one row, Shift extends from the anchor in either direction")
    func selectionModifiers() {
        let ids = (0..<5).map { _ in UUID() }
        #expect(ShelfSelection.toggling([ids[0]], ids[1]) == Set([ids[0], ids[1]]))
        #expect(ShelfSelection.toggling([ids[0], ids[1]], ids[1]) == Set([ids[0]]))

        #expect(ShelfSelection.extending(from: ids[1], to: ids[3], in: ids)
                == Set(ids[1...3]))
        #expect(ShelfSelection.extending(from: ids[3], to: ids[1], in: ids)
                == Set(ids[1...3]))
        // No anchor, or an anchor that is gone, falls back to the clicked row alone.
        #expect(ShelfSelection.extending(from: nil, to: ids[2], in: ids) == Set([ids[2]]))
        #expect(ShelfSelection.extending(from: UUID(), to: ids[2], in: ids) == Set([ids[2]]))
    }

    @Test("A drag carries the whole selection only when it starts inside it")
    func dragScope() {
        let ids = (0..<3).map { _ in UUID() }
        let selection = Set([ids[0], ids[1]])
        #expect(ShelfSelection.dragging(ids[0], selection: selection) == selection)
        #expect(ShelfSelection.dragging(ids[2], selection: selection) == Set([ids[2]]))
        // Rows removed elsewhere cannot linger in the selection.
        #expect(ShelfSelection.retained(selection, in: [ids[1], ids[2]]) == Set([ids[1]]))
    }

    @Test("Each order has one sensible direction: newest first, or names A to Z")
    func ordering() throws {
        let now = Date()
        let items = [
            ShelfItem(url: URL(fileURLWithPath: "/f/beta.txt"), name: "beta.txt",
                      bookmarkData: Data(), addedAt: now.addingTimeInterval(-60)),
            ShelfItem(url: URL(fileURLWithPath: "/f/item 10.txt"), name: "item 10.txt",
                      bookmarkData: Data(), addedAt: now),
            ShelfItem(url: URL(fileURLWithPath: "/f/item 2.txt"), name: "item 2.txt",
                      bookmarkData: Data(), addedAt: now.addingTimeInterval(-120))
        ]
        let byDate = ShelfDocument(items: items, sort: .dateAdded).ordered()
        #expect(byDate.map(\.name) == ["item 10.txt", "beta.txt", "item 2.txt"])
        // Natural ordering, so "item 2" precedes "item 10".
        let byName = ShelfDocument(items: items, sort: .name).ordered()
        #expect(byName.map(\.name) == ["beta.txt", "item 2.txt", "item 10.txt"])
        let smartInput = ShelfDocument(items: items, sort: .smart).ordered()
        #expect(smartInput.map(\.name) == byName.map(\.name))
    }

    @Test("Sort and layout choices persist with the items")
    func viewChoicesPersist() throws {
        let suite = "ShelfView.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let shelf = controller(defaults)
        shelf.start()
        #expect(shelf.sort == .dateAdded && shelf.presentation == .list)
        try shelf.setSort(.name)
        try shelf.setPresentation(.grid)
        try shelf.setSort(.smart)

        let reloaded = controller(defaults)
        reloaded.start()
        #expect(reloaded.sort == .smart && reloaded.presentation == .grid)
        // A document written before these existed still opens, on the defaults.
        defaults.set(Data(#"{"version":1,"items":[]}"#.utf8), forKey: "dock.shelf.v1")
        let legacy = try #require(try ShelfRepository(defaults: defaults).load())
        #expect(legacy.sort == .dateAdded && legacy.presentation == .list)
    }

    @Test("An empty Shelf still renders its tile, and a hidden one leaves no entry")
    func tileVisibility() {
        let shelf = ShelfDockItem(count: 0, icon: NSImage())
        #expect(shelf.isEmpty)
        let shown = DockSectionProjection.entries(items: [], visibility: .showAll, expanded: true, shelf: shelf)
        #expect(shown.map(\.target) == [.shelf])
        let hidden = DockSectionProjection.entries(items: [], visibility: .showAll, expanded: true, shelf: nil)
        #expect(hidden.isEmpty)
    }

    @Test("Smart Shelf changes silently warm the current semantic request")
    func smartWarmup() async {
        let organizer = RecordingSemanticOrganizer()
        let request = semanticRequest()
        let warmup = ShelfSemanticWarmupController(
            organizer: organizer,
            makeRequest: { request },
            delay: {},
            isLowPowerModeEnabled: { false }
        )

        warmup.schedule(enabled: true)
        await warmup.waitUntilIdle()

        #expect(await organizer.requests == [request])
    }

    @Test("Warm-up stays idle when Smart is disabled or Low Power Mode is active")
    func guardedWarmup() async {
        let organizer = RecordingSemanticOrganizer()
        let request = semanticRequest()
        let disabled = ShelfSemanticWarmupController(
            organizer: organizer,
            makeRequest: { request },
            delay: {},
            isLowPowerModeEnabled: { false }
        )
        disabled.schedule(enabled: false)
        await disabled.waitUntilIdle()

        let lowPower = ShelfSemanticWarmupController(
            organizer: organizer,
            makeRequest: { request },
            delay: {},
            isLowPowerModeEnabled: { true }
        )
        lowPower.schedule(enabled: true)
        await lowPower.waitUntilIdle()

        #expect(await organizer.requests.isEmpty)
    }

    @Test("Warm-up and an open panel share one in-flight generation")
    func coalescedSemanticGeneration() async throws {
        let base = BlockingSemanticOrganizer()
        let organizer = CoalescingSemanticStackOrganizer(base: base)
        let request = semanticRequest()
        let firstStream = await organizer.snapshots(for: request)
        let first = Task { try await Self.collect(firstStream) }
        await base.waitUntilSubscribed()

        let secondStream = await organizer.snapshots(for: request)
        let second = Task { try await Self.collect(secondStream) }
        let expected = SemanticStackSnapshot(sections: [], isFinal: true)
        await base.finish(with: expected)

        #expect(try await first.value == [expected])
        #expect(try await second.value == [expected])
        #expect(await base.starts == 1)
    }

    @Test("A newer Shelf change cancels the older debounce")
    func warmupDebounceKeepsLatestRequest() async {
        let organizer = RecordingSemanticOrganizer()
        let delay = FirstDelayBlocksUntilCancelled()
        let request = semanticRequest()
        let warmup = ShelfSemanticWarmupController(
            organizer: organizer,
            makeRequest: { request },
            delay: { try await delay.wait() },
            isLowPowerModeEnabled: { false }
        )

        warmup.schedule(enabled: true)
        await delay.waitUntilStarted()
        warmup.schedule(enabled: true)
        await warmup.waitUntilIdle()

        #expect(await organizer.requests == [request])
    }

    private func semanticRequest() -> SemanticStackRequest {
        SemanticStackRequest(
            source: .shelf,
            candidates: (0..<4).map {
                SemanticStackCandidate(
                    id: "item-\($0)", name: "Item \($0)", kind: "txt", contentType: "public.text",
                    isDirectory: false, byteCount: 4, createdAt: nil, modifiedAt: nil, addedAt: nil
                )
            },
            localeIdentifier: "en"
        )
    }

    private static func collect(
        _ stream: AsyncThrowingStream<SemanticStackSnapshot, Error>
    ) async throws -> [SemanticStackSnapshot] {
        var snapshots: [SemanticStackSnapshot] = []
        for try await snapshot in stream { snapshots.append(snapshot) }
        return snapshots
    }
}

private actor RecordingSemanticOrganizer: SemanticStackOrganizing {
    private(set) var requests: [SemanticStackRequest] = []

    func availability() -> SemanticStackAvailability { .available }

    func snapshots(
        for request: SemanticStackRequest
    ) -> AsyncThrowingStream<SemanticStackSnapshot, Error> {
        requests.append(request)
        return AsyncThrowingStream { continuation in
            continuation.yield(SemanticStackSnapshot(sections: [], isFinal: true))
            continuation.finish()
        }
    }
}

private actor BlockingSemanticOrganizer: SemanticStackOrganizing {
    private(set) var starts = 0
    private var continuation: AsyncThrowingStream<SemanticStackSnapshot, Error>.Continuation?
    private var subscriptionWaiters: [CheckedContinuation<Void, Never>] = []

    func availability() -> SemanticStackAvailability { .available }

    func snapshots(
        for request: SemanticStackRequest
    ) -> AsyncThrowingStream<SemanticStackSnapshot, Error> {
        starts += 1
        var captured: AsyncThrowingStream<SemanticStackSnapshot, Error>.Continuation?
        let stream = AsyncThrowingStream<SemanticStackSnapshot, Error> { captured = $0 }
        continuation = captured
        subscriptionWaiters.forEach { $0.resume() }
        subscriptionWaiters.removeAll()
        return stream
    }

    func waitUntilSubscribed() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { subscriptionWaiters.append($0) }
    }

    func finish(with snapshot: SemanticStackSnapshot) {
        continuation?.yield(snapshot)
        continuation?.finish()
        continuation = nil
    }
}

private actor FirstDelayBlocksUntilCancelled {
    private var calls = 0
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async throws {
        calls += 1
        if calls == 1 {
            startWaiters.forEach { $0.resume() }
            startWaiters.removeAll()
            try await Task.sleep(for: .seconds(60))
        }
    }

    func waitUntilStarted() async {
        guard calls == 0 else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }
}
