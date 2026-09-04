import Foundation
import Testing

@MainActor
struct DockModelTests {
    private func app(_ id: String, name: String? = nil, path: String? = nil) -> ApplicationReference {
        ApplicationReference(bundleIdentifier: id, url: URL(fileURLWithPath: path ?? "/Applications/\(id).app"), name: name ?? id)
    }

    @Test("Placement preserves negative display origins and the visible-frame bottom")
    func placement() {
        let screen = CGRect(x: -1920, y: -360, width: 1920, height: 1000)
        let layout = DockGeometry.layout(count: 8, favoriteCount: 4, availableLength: screen.width)
        let frame = DockGeometry.panelFrame(referenceFrame: screen, layout: layout, settings: .defaults)
        #expect(frame.midX == screen.midX)
        #expect(frame.minY + DockGeometry.outerMargin == screen.minY + 8)
        #expect(frame.minX >= screen.minX)
        #expect(frame.maxX <= screen.maxX)
    }

    @Test("Magnification stays bounded and derives from unchanged resting positions")
    func magnification() {
        let layout = DockGeometry.layout(count: 8, favoriteCount: 4, availableLength: 1400)
        let resting = layout.restingCenters
        let pointer = resting[3]
        let sizes = layout.sizes(pointerAlong: pointer, reduceMotion: false)
        #expect(abs(sizes[3] - layout.iconSize * 1.4) < 0.001)
        #expect(sizes.allSatisfy { $0 >= layout.iconSize && $0 <= layout.iconSize * 1.4 })
        #expect(sizes[2] > layout.iconSize)
        #expect(sizes[7] == layout.iconSize)
        let expanded = layout.centers(sizes: sizes)
        #expect(expanded[2] + sizes[2] / 2 < expanded[3] - sizes[3] / 2)
        #expect(layout.restingCenters == resting)
        #expect(layout.sizes(pointerAlong: pointer, reduceMotion: false) == sizes)
        #expect(layout.sizes(pointerAlong: pointer, reduceMotion: true).allSatisfy { $0 == layout.iconSize })
        #expect(layout.sizes(pointerAlong: nil, reduceMotion: false).allSatisfy { $0 == layout.iconSize })
    }

    @Test("Magnification keeps the glass fixed while buttons grow above it from the same baseline")
    func fixedSurfaceHeight() {
        for width: CGFloat in [560, 1400] {
            let layout = DockGeometry.layout(count: 10, favoriteCount: 3, availableLength: width)
            let resting = layout.sizes(pointerAlong: nil, reduceMotion: false)
            let magnified = layout.sizes(pointerAlong: layout.restingCenters[4], reduceMotion: false)
            let glass = layout.surfaceFrame(sizes: resting)
            let hoveredGlass = layout.surfaceFrame(sizes: magnified)
            #expect(glass.minY == hoveredGlass.minY)
            #expect(glass.height == hoveredGlass.height)
            #expect(glass.maxY == hoveredGlass.maxY)
            #expect(hoveredGlass.width > glass.width)
            let restingButton = layout.buttonFrame(centerAlong: layout.restingCenters[4], size: resting[4])
            let hoveredButton = layout.buttonFrame(centerAlong: layout.centers(sizes: magnified)[4], size: magnified[4])
            #expect(restingButton.maxY == hoveredButton.maxY)
            #expect(hoveredButton.minY < hoveredGlass.minY)
            #expect(hoveredButton.minY > 0)
            let exposedPoint = CGPoint(x: hoveredButton.midX, y: hoveredButton.minY + 0.1)
            #expect(hoveredButton.contains(exposedPoint))
            #expect(!hoveredGlass.contains(exposedPoint))
        }
    }

    @Test("Crowded docks shrink to 32 points, then provide a wider scrollable canvas")
    func overflow() {
        let normal = DockGeometry.layout(count: 5, favoriteCount: 3, availableLength: 1400)
        #expect(normal.iconSize == 48)
        let compact = DockGeometry.layout(count: 10, favoriteCount: 3, availableLength: 560)
        #expect(compact.iconSize >= 32 && compact.iconSize < 48)
        let overflow = DockGeometry.layout(count: 40, favoriteCount: 3, availableLength: 560)
        #expect(overflow.iconSize == 32)
        #expect(overflow.viewportLength <= 560)
        #expect(overflow.canvasLength > overflow.viewportLength)
    }

    @Test("Utility entries receive a divider independent of the pinned and running divider")
    func utilityDividers() {
        let divided = DockGeometry.layout(count: 6, favoriteCount: 3, utilityCount: 1,
                                          availableLength: 1400)
        #expect(divided.separatorIndices == [3, 5])
        let pinnedOnly = DockGeometry.layout(count: 4, favoriteCount: 3, utilityCount: 1,
                                             availableLength: 1400)
        #expect(pinnedOnly.separatorIndices == [3])
        let utilityOnly = DockGeometry.layout(count: 1, favoriteCount: 0, utilityCount: 1,
                                              availableLength: 1400)
        #expect(utilityOnly.separatorIndices.isEmpty)
    }

    @Test("Running apps deduplicate and retain order across launch and termination")
    func ordering() {
        let a = app("a", name: "Alpha")
        let b = app("b", name: "Bravo")
        let c = app("c", name: "Charlie")
        let duplicateA = app("a", name: "Alpha", path: "/Other/Alpha.app")
        let initial = DockOrdering.runningOrder(previous: [], current: [c, a, b, duplicateA])
        #expect(initial == ["a", "b", "c"])
        let next = DockOrdering.runningOrder(previous: initial, current: [c, app("0", name: "Aardvark"), a])
        #expect(next == ["a", "c", "0"])
        #expect(DockOrdering.itemOrder(favorites: [c, c], runningIDs: next) == ["c", "a", "0"])
        #expect(DockOrdering.itemOrder(favorites: [], runningIDs: next) == next)
    }

    @Test("Favorites seed once, preserve removal of every favorite, and keep missing references")
    func persistence() throws {
        let suite = "DeeDockTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = FavoritesRepository(defaults: defaults)
        let seed = app("a")
        #expect(try repository.load { [seed, seed] } == [seed])
        #expect(try repository.load { [app("b")] } == [seed])
        let missing = app("missing", path: "/NoLongerInstalled/Missing.app")
        try repository.save([missing, seed])
        #expect(try repository.load { [] } == [missing, seed])
        try repository.save([])
        #expect(try repository.load { [seed] }.isEmpty)
    }

    @Test("Unreadable favorites are surfaced without overwriting their saved bytes")
    func corruptPersistence() throws {
        let suite = "DeeDockTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let badData = Data("broken".utf8)
        defaults.set(badData, forKey: "dock.favorites.v1")
        let repository = FavoritesRepository(defaults: defaults)
        #expect(throws: (any Error).self) { try repository.load { [] } }
        #expect(defaults.data(forKey: "dock.favorites.v1") == badData)
    }
}
