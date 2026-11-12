import Foundation
import Testing
@testable import DeeDock

/// The orb's pile physics, driven with simulated time: bodies settle inside the glass without
/// overlapping, the world goes to sleep (so the view's timeline can pause), and the leave
/// effects remove bodies promptly.
struct VaporPhysicsTests {
    private let frame = 1.0 / 60

    private func ids(_ count: Int) -> [UUID] { (0..<count).map { _ in UUID() } }

    /// Six folders of different sizes dropped one after another, as Add All does.
    private func droppedPile(seed: UInt64 = 1) -> VaporPhysicsWorld {
        var world = VaporPhysicsWorld(seed: seed)
        let sizes: [Int64] = [9_800_000_000, 1_310_000_000, 486_000_000, 211_000_000, 12_600_000, 22_400_000]
        for (index, id) in ids(sizes.count).enumerated() {
            world.spawn(id, radius: VaporPileSizing.radius(bytes: sizes[index]), style: .drop, delay: Double(index) * 0.09)
        }
        return world
    }

    /// Advances in 60 Hz frames until the world sleeps or `limit` seconds pass.
    private func runUntilAsleep(_ world: inout VaporPhysicsWorld, limit: Double = 8) {
        var time = 0.0
        while !world.isAsleep, time < limit {
            world.advance(by: frame)
            time += frame
        }
    }

    private func expectInsideGlass(_ world: VaporPhysicsWorld) {
        for body in world.bodies {
            let distance = (body.position * body.position).sum().squareRoot()
            #expect(distance <= world.innerRadius - body.radius * 0.9 + 0.5)
        }
    }

    private func expectNoDeepOverlaps(_ world: VaporPhysicsWorld) {
        let bodies = world.bodies
        for i in bodies.indices {
            for j in bodies.indices where j > i {
                let delta = bodies[i].position - bodies[j].position
                let distance = (delta * delta).sum().squareRoot()
                #expect(distance >= (bodies[i].radius + bodies[j].radius) * 0.85)
            }
        }
    }

    @Test func droppedFoldersSettleInsideTheGlassAndSleep() {
        var world = droppedPile()
        #expect(!world.isAsleep)
        runUntilAsleep(&world)
        #expect(world.isAsleep)
        #expect(world.bodies.count == 6)
        // Well within the quiet limit: the pile actually came to rest.
        #expect(world.elapsed < 4)
        expectInsideGlass(world)
        expectNoDeepOverlaps(world)
        // Gravity pulled everything into the lower half.
        let meanY = world.bodies.map(\.position.y).reduce(0, +) / Double(world.bodies.count)
        #expect(meanY > 0)
    }

    @Test func aSleepingWorldDoesNotMove() {
        var world = droppedPile()
        runUntilAsleep(&world)
        let before = world.bodies
        world.advance(by: 1)
        #expect(world.bodies == before)
        #expect(world.isAsleep)
    }

    @Test func settledSpawnsArePlacedAtRestWithoutParticles() {
        var world = VaporPhysicsWorld(seed: 3)
        for id in ids(5) {
            world.spawn(id, radius: 12, style: .settled)
            // Each settled spawn is immediately at rest: Reduce Motion shows no motion.
            #expect(world.isAsleep)
        }
        #expect(world.particles.isEmpty)
        #expect(world.bodies.allSatisfy { $0.velocity == .zero && $0.scale == 1 })
        expectInsideGlass(world)
        expectNoDeepOverlaps(world)
    }

    @Test func aCrowdedPileShrinksToFit() {
        var world = VaporPhysicsWorld(seed: 4)
        for id in ids(30) { world.spawn(id, radius: 15.5, style: .settled) }
        let radius = world.bodies[0].radius
        #expect(radius < 15.5 * 0.7)
        expectInsideGlass(world)
        let area = world.bodies.reduce(0) { $0 + $1.radius * $1.radius }
        #expect(area <= 0.53 * world.innerRadius * world.innerRadius)
    }

    @Test func evaporateRemovesEveryBodyWithinOneAndAHalfSeconds() {
        var world = droppedPile()
        runUntilAsleep(&world)
        world.evaporate(Set(world.memberIDs), reduceMotion: false)
        #expect(!world.isAsleep)
        var time = 0.0, sawSteam = false
        while !world.bodies.isEmpty, time < 3 {
            world.advance(by: frame)
            time += frame
            sawSteam = sawSteam || world.particles.contains { $0.kind == .steam }
        }
        #expect(world.bodies.isEmpty)
        #expect(time <= 1.5)
        #expect(sawSteam)
        // Steam rises: some of it leaves the glass through the top.
        var escaped = false
        while !world.particles.isEmpty, time < 5 {
            world.advance(by: frame)
            time += frame
            escaped = escaped || world.particles.contains { $0.position.y < -world.innerRadius }
        }
        #expect(escaped)
        runUntilAsleep(&world)
        #expect(world.isAsleep)
    }

    @Test func evaporateUnderReduceMotionFadesWithoutParticles() {
        var world = VaporPhysicsWorld(seed: 5)
        for id in ids(4) { world.spawn(id, radius: 11, style: .settled) }
        world.evaporate(Set(world.memberIDs), reduceMotion: true)
        var time = 0.0
        while !world.bodies.isEmpty, time < 2 {
            world.advance(by: frame)
            time += frame
            #expect(world.particles.isEmpty)
        }
        #expect(world.bodies.isEmpty)
        #expect(time <= 0.4)
    }

    @Test func evaporateWaitsForItsDelayAndGoesTopFirst() {
        var world = droppedPile()
        runUntilAsleep(&world)
        let top = world.bodies.min { $0.position.y < $1.position.y }!.folderID
        world.evaporate(Set(world.memberIDs), delay: 0.5, reduceMotion: false)
        world.advance(by: 0.03)
        // Still waiting: nothing has started leaving.
        #expect(world.bodies.allSatisfy { $0.state == .live })
        for _ in 0..<30 { world.advance(by: frame) }
        let leaving = world.bodies.filter { $0.state == .evaporating }.map(\.folderID)
        #expect(leaving == [top])
    }

    @Test func removingPopsWithSparks() {
        var world = VaporPhysicsWorld(seed: 6)
        let id = UUID()
        world.spawn(id, radius: 12, style: .settled)
        world.remove(id, reduceMotion: false)
        #expect(world.particles.filter { $0.kind == .spark }.count == 8)
        #expect(!world.contains(id))
        for _ in 0..<20 { world.advance(by: frame) }
        #expect(world.bodies.isEmpty)
    }

    @Test func sloshWakesAndMovesTheSettledPile() {
        var world = droppedPile()
        runUntilAsleep(&world)
        let before = world.bodies.map(\.position)
        world.setMotion(acceleration: SIMD2(9_000, 0))
        #expect(!world.isAsleep)
        for _ in 0..<6 { world.advance(by: frame) }
        let moved = zip(before, world.bodies.map(\.position)).contains { (($0 - $1) * ($0 - $1)).sum() > 1 }
        #expect(moved)
        // The contents lag behind the glass: pushing the orb right moves them left.
        let shift = zip(before, world.bodies.map(\.position)).map { $1.x - $0.x }.reduce(0, +)
        #expect(shift < 0)
        // With no further samples the push decays and the pile settles again.
        runUntilAsleep(&world)
        #expect(world.isAsleep)
        expectInsideGlass(world)
    }

    @Test func respawningAfterAnEvaporateKeepsOneMemberPerFolder() {
        var world = VaporPhysicsWorld(seed: 8)
        let id = UUID()
        world.spawn(id, radius: 10, style: .settled)
        world.evaporate([id], reduceMotion: false)
        #expect(!world.contains(id))
        // Undo puts the folder back while its old body is still rising.
        world.spawn(id, radius: 10, style: .restore)
        world.spawn(id, radius: 10, style: .restore)
        #expect(world.memberIDs == [id])
    }

    @Test func bigFoldersGetBiggerBodiesOnALogScale() {
        let small = VaporPileSizing.radius(bytes: 2_000_000)
        let medium = VaporPileSizing.radius(bytes: 200_000_000)
        let large = VaporPileSizing.radius(bytes: 20_000_000_000)
        #expect(small < medium && medium < large)
        #expect(small >= 7.5 && large <= 15.5)
        #expect(VaporPileSizing.radius(for: .pending) == VaporPileSizing.pendingRadius)
        #expect(VaporPileSizing.fitScale(radii: [10, 10], innerRadius: 53) == 1)
    }
}
