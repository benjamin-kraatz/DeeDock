import Foundation
import Testing

struct StackGravityPhysicsTests {
    private func configuration(strength: CGFloat = 1, iconSize: CGFloat = 48, spacing: CGFloat = 4) -> StackGravityPhysics.Configuration {
        StackGravityPhysics.Configuration(strength: strength, iconSize: iconSize, itemSpacing: spacing)
    }

    @Test("Nearby icons move toward a stack; the stack itself does not")
    func softPullTowardWell() {
        let centers: [CGFloat] = [40, 100, 160, 220]
        let offsets = StackGravityPhysics.pullOffsets(
            centers: centers,
            wellIndices: [2],
            configuration: configuration()
        )
        #expect(offsets.count == 4)
        #expect(offsets[2] == 0)
        #expect(offsets[1] > 0)
        #expect(offsets[3] < 0)
        #expect(abs(offsets[0]) < abs(offsets[1]))
        let pulled = StackGravityPhysics.pulledCenters(
            centers: centers,
            wellIndices: [2],
            configuration: configuration()
        )
        #expect(pulled[1] > centers[1])
        #expect(pulled[3] < centers[3])
        #expect(pulled[1] < pulled[2])
        #expect(pulled[2] < pulled[3])
    }

    @Test("Zero strength and missing wells leave centers unchanged")
    func disabledPull() {
        let centers: [CGFloat] = [40, 100, 160]
        #expect(StackGravityPhysics.pullOffsets(
            centers: centers,
            wellIndices: [1],
            configuration: configuration(strength: 0)
        ) == [0, 0, 0])
        #expect(StackGravityPhysics.pullOffsets(
            centers: centers,
            wellIndices: [],
            configuration: configuration()
        ) == [0, 0, 0])
    }

    @Test("Stronger settings increase the pull without reversing item order")
    func strengthScalesPull() {
        let centers: [CGFloat] = [50, 120, 190]
        let light = StackGravityPhysics.pullOffsets(
            centers: centers, wellIndices: [1], configuration: configuration(strength: 0.25)
        )
        let heavy = StackGravityPhysics.pullOffsets(
            centers: centers, wellIndices: [1], configuration: configuration(strength: 1)
        )
        #expect(abs(heavy[0]) > abs(light[0]))
        #expect(abs(heavy[2]) > abs(light[2]))
        let pulled = StackGravityPhysics.pulledCenters(
            centers: centers, wellIndices: [1], configuration: configuration(strength: 1)
        )
        #expect(pulled[0] < pulled[1])
        #expect(pulled[1] < pulled[2])
    }

    @Test("Release inside a well snaps before or after that stack")
    func snapBesideWell() {
        let pins: [DockPin] = [
            .application(DisplayFixtures.app("safari")),
            .application(DisplayFixtures.app("mail")),
            .folder(FolderReference(url: URL(fileURLWithPath: "/Fixtures/Docs"), name: "Docs",
                                    bookmarkData: Data("bookmark".utf8))),
            .application(DisplayFixtures.app("calendar")),
        ]
        let wells = StackGravityPhysics.wellPinIndices(in: pins)
        #expect(wells == [2])
        let centers: [CGFloat] = [40, 100, 160, 220]
        let config = configuration()
        let before = try #require(StackGravityPhysics.snap(
            along: 150, pinCenters: centers, wellPinIndices: wells, configuration: config
        ))
        #expect(before.wellPinIndex == 2)
        #expect(before.pinIndex == 2)
        let after = try #require(StackGravityPhysics.snap(
            along: 175, pinCenters: centers, wellPinIndices: wells, configuration: config
        ))
        #expect(after.pinIndex == 3)
        #expect(StackGravityPhysics.snap(
            along: 40, pinCenters: centers, wellPinIndices: wells, configuration: config
        ) == nil)
        #expect(StackGravityPhysics.snap(
            along: 160, pinCenters: centers, wellPinIndices: wells, configuration: config,
            ignoredPinIndex: 2
        ) == nil)
    }

    @Test("Focus mute is a quarter of the configured strength")
    func muteFactor() {
        #expect(StackGravityPhysics.focusMuteFactor == 0.25)
    }
}

@MainActor
struct StackGravityStoreTests {
    private func store(_ suite: String) throws -> (StackGravityStore, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (StackGravityStore(repository: StackGravityRepository(defaults: defaults)), defaults)
    }

    @Test("Settings persist and Focus mute or disable changes effective strength")
    func persistenceAndFocus() throws {
        let suite = "GravitySettings.\(UUID().uuidString)"
        let (gravity, defaults) = try store(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        gravity.start()
        #expect(gravity.isEnabled)
        #expect(gravity.effectiveStrength == 0.4)
        gravity.setStrength(0.8)
        gravity.setFocusBehavior(.mute)
        gravity.setFocusActive(true)
        #expect(gravity.effectiveStrength == 0.2)
        gravity.setFocusBehavior(.disable)
        #expect(gravity.effectiveStrength == 0)
        gravity.setFocusBehavior(.keep)
        #expect(gravity.effectiveStrength == 0.8)
        gravity.setEnabled(false)
        #expect(gravity.effectiveStrength == 0)

        let reloaded = StackGravityStore(repository: StackGravityRepository(defaults: defaults))
        reloaded.start()
        #expect(reloaded.strength == 0.8)
        #expect(reloaded.focusBehavior == .keep)
        #expect(!reloaded.isEnabled)
    }

    @Test("Unreadable bytes freeze edits until an explicit reset")
    func corruptDocument() throws {
        let suite = "GravityCorrupt.\(UUID().uuidString)"
        let (gravity, defaults) = try store(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not-json".utf8), forKey: "dock.stack-gravity.v1")
        gravity.start()
        #expect(gravity.requiresReset)
        gravity.setStrength(1)
        #expect(gravity.strength == 0.4)
        gravity.reset()
        #expect(!gravity.requiresReset)
        gravity.setStrength(0.55)
        #expect(gravity.strength == 0.55)
    }

    @Test("Snap undo is per display and can be consumed once")
    func undoLifecycle() throws {
        let suite = "GravityUndo.\(UUID().uuidString)"
        let (gravity, defaults) = try store(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        gravity.start()
        let safari = DockPin.application(DisplayFixtures.app("safari"))
        let mail = DockPin.application(DisplayFixtures.app("mail"))
        gravity.notePendingSnap(
            StackGravityPendingSnap(displayID: "display.a", stackName: "Docs", pinIndex: 1, wellPinIndex: 1)
        )
        gravity.registerUndo(
            StackGravityUndo(displayID: "display.a", previousPins: [safari, mail], stackName: "Docs")
        )
        #expect(gravity.pendingSnap == nil)
        #expect(gravity.undo(for: "display.b") == nil)
        let record = try #require(gravity.consumeUndo(for: "display.a"))
        #expect(record.previousPins == [safari, mail])
        #expect(gravity.consumeUndo(for: "display.a") == nil)
    }
}
