import CoreGraphics
import Foundation
import Testing

@MainActor
struct DockMagneticPlacementTests {
    @Test("Parked frames persist per display and drop when the pin is gone")
    func storeRoundTrip() throws {
        let suite = "DeeDockMagneticPlacement.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DockMagneticPlacementStore(defaults: defaults)
        let placement = DockMagneticPlacement(
            pinID: "a",
            frame: CGRect(x: -100, y: 20, width: 48, height: 48)
        )
        store.place(placement, on: "display.one")
        #expect(store.placements(for: "display.one") == [placement])
        #expect(store.placedIDs(for: "display.one") == ["a"])
        #expect(store.frames(for: "display.one", excluding: "a").isEmpty)
        #expect(store.frames(for: "display.one", excluding: "b") == [placement.frame])

        store.retain(pinIDs: ["other"], on: "display.one")
        #expect(store.placements(for: "display.one").isEmpty)

        store.place(placement, on: "display.one")
        store.clear(pinID: "a", on: "display.one")
        #expect(store.placements(for: "display.one").isEmpty)

        store.place(placement, on: "display.one")
        let reloaded = DockMagneticPlacementStore(defaults: defaults)
        #expect(reloaded.placements(for: "display.one") == [placement])
    }
}
