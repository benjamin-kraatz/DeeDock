import Foundation
import Testing
@testable import DeeDock

/// How the orb's pile follows the controller's folders and events.
@MainActor
struct VaporPileEngineTests {
    private let folders = VaporPreviewData.pile

    @Test func firstSyncPlacesTheFoldersAlreadySettled() {
        let engine = VaporPileEngine(seed: 2)
        engine.sync(folders: folders, addition: nil, deletion: nil, isStaging: false, reduceMotion: false)
        #expect(engine.world.isAsleep)
        #expect(!engine.isRunning)
        #expect(Set(engine.world.memberIDs) == Set(folders.map(\.id)))
    }

    @Test func anAdditionDropsInAndRunsTheTimeline() {
        let engine = VaporPileEngine(seed: 2)
        engine.sync(folders: Array(folders.prefix(2)), addition: nil, deletion: nil, isStaging: false, reduceMotion: false)
        let added = Array(folders[2...3])
        let addition = VaporEvent(VaporAddition(folderIDs: added.map(\.id), source: .drop))
        engine.sync(folders: Array(folders.prefix(4)), addition: addition, deletion: nil, isStaging: false, reduceMotion: false)
        #expect(engine.isRunning)
        #expect(!engine.world.isAsleep)
        // The second folder waits for its stagger.
        #expect(engine.world.bodies.count == 3)
        #expect(added.allSatisfy { engine.world.contains($0.id) })
    }

    @Test func aDeletionEvaporatesAndStagedFoldersAreNotRespawned() {
        let engine = VaporPileEngine(seed: 2)
        engine.sync(folders: folders, addition: nil, deletion: nil, isStaging: false, reduceMotion: false)
        let deletion = VaporEvent(VaporDeletion(folders: folders, fromPanel: false))
        engine.sync(folders: folders, addition: nil, deletion: deletion, isStaging: true, reduceMotion: false)
        #expect(engine.world.memberIDs.isEmpty)
        #expect(engine.isRunning)
        // Staging finished: one folder failed and stays in the orb, so it drops back in.
        let failed = [folders[0]]
        engine.sync(folders: failed, addition: nil, deletion: deletion, isStaging: false, reduceMotion: false)
        #expect(engine.world.memberIDs == [failed[0].id])
    }

    @Test func clearingPopsEveryBody() {
        let engine = VaporPileEngine(seed: 2)
        engine.sync(folders: folders, addition: nil, deletion: nil, isStaging: false, reduceMotion: false)
        engine.sync(folders: [], addition: nil, deletion: nil, isStaging: false, reduceMotion: false)
        #expect(engine.world.memberIDs.isEmpty)
        #expect(engine.isRunning)
    }

    @Test func reduceMotionIgnoresSlosh() {
        let engine = VaporPileEngine(seed: 2)
        engine.sync(folders: folders, addition: nil, deletion: nil, isStaging: false, reduceMotion: true)
        engine.setMotion(VaporOrbMotion(isDragging: true, velocity: .zero, acceleration: CGVector(dx: 9_000, dy: 0)),
                         reduceMotion: true)
        #expect(engine.world.isAsleep)
        #expect(!engine.isRunning)
    }

    @Test func theTimelinePausesOnceThePileSleeps() async {
        let engine = VaporPileEngine(seed: 2)
        engine.sync(folders: [], addition: nil, deletion: nil, isStaging: false, reduceMotion: false)
        let addition = VaporEvent(VaporAddition(folderIDs: [folders[0].id], source: .drop))
        engine.sync(folders: [folders[0]], addition: addition, deletion: nil, isStaging: false, reduceMotion: false)
        #expect(engine.isRunning)
        var date = Date(timeIntervalSinceReferenceDate: 0)
        for _ in 0..<600 where !engine.world.isAsleep {
            date += 1.0 / 60
            _ = engine.frame(at: date)
        }
        #expect(engine.world.isAsleep)
        await vaporSettle { !engine.isRunning }
        #expect(!engine.isRunning)
    }
}
