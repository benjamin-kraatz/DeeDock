import Foundation

/// One folder icon tumbling inside the orb.
///
/// Positions are in points relative to the orb's centre, y down (SwiftUI's axes), so a body
/// resting at the bottom of the sphere has a positive `y`.
nonisolated struct VaporBody: Equatable, Sendable {
    enum State: Equatable, Sendable {
        /// Falls, collides and rests in the pile.
        case live
        /// Rises and fades while giving off steam (the delete effect).
        case evaporating
        /// Swells and fades with a few sparks (taken out without deleting).
        case popping
        /// Fades in place (Reduce Motion's version of both).
        case fading
    }

    var folderID: UUID
    var position: SIMD2<Double>
    var velocity: SIMD2<Double>
    /// Rotation in radians.
    var angle: Double
    /// Angular velocity in radians per second.
    var spin: Double
    /// The radius from the folder's size, before fitting the pile into the orb.
    var baseRadius: Double
    /// The collision radius now; eases toward `baseRadius` times the pile's fit factor.
    var radius: Double
    /// Draw scale: pops in from 0.25 and swells while leaving.
    var scale: Double
    var alpha: Double
    var state: State = .live
    /// A state the body switches to after `scheduleDelay` seconds. It stays live meanwhile,
    /// which is how evaporating bodies leave one after another.
    var scheduledState: State?
    var scheduleDelay: Double = 0
    /// Fractional steam particles owed, so emission is a steady rate whatever the step size.
    var emitBudget: Double = 0

    /// The body is in the pile and not already on its way out.
    var isSettledMember: Bool { state == .live && scheduledState == nil }
}

/// A steam puff or spark. Drawn without the sphere's clip, so steam can rise out of the glass.
nonisolated struct VaporParticle: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case steam, spark }

    var kind: Kind
    var position: SIMD2<Double>
    var velocity: SIMD2<Double>
    var radius: Double
    var life: Double = 0
    var lifetime: Double

    /// 1 when born, falling linearly to 0 at the end of its life.
    var opacity: Double { max(0, 1 - life / lifetime) }
}

/// The 2D physics of the folders inside the orb: gravity, circle–circle collisions, the
/// spherical boundary, spin from tangential contact, slosh from the orb's acceleration, the
/// spawn pop, fit-to-orb shrinking, and the leave effects (evaporate, pop, fade).
///
/// A value type with no clock and no actor: ``advance(by:)`` integrates in fixed substeps of
/// ``substep`` seconds, so the result does not depend on the frame rate, and tests can drive
/// it with simulated time. Randomness comes from a seeded generator.
///
/// The world **sleeps** once nothing moves: no particles, no leaving bodies, no pending
/// spawns, no slosh, and every body slow for ``restDuration`` (or simply quiet for
/// ``quietLimit``, which bounds how long a jittery stack can keep it awake). While asleep,
/// ``advance(by:)`` does nothing, and the view pauses its timeline. Any change wakes it.
nonisolated struct VaporPhysicsWorld: Sendable {
    /// How the body enters the orb.
    enum SpawnStyle: Equatable, Sendable {
        /// Drops in at the top and pops from small to full size.
        case drop
        /// Like `drop`, but falls gently (Undo putting folders back).
        case restore
        /// Placed already settled, with no visible motion (launch and Reduce Motion).
        case settled
    }

    private struct PendingSpawn: Sendable {
        var folderID: UUID
        var radius: Double
        var style: SpawnStyle
        var delay: Double
    }

    /// The fixed integration step.
    static let substep: Double = 1.0 / 180
    /// The longest frame integrated at once; longer gaps (a paused timeline) are cut short.
    static let maxFrame: Double = 1.0 / 30
    /// Bodies slower than this count as resting.
    static let restSpeed: Double = 12
    static let restDuration: Double = 0.4
    static let quietLimit: Double = 3
    /// Seconds between bodies leaving when several evaporate.
    static let evaporateStagger: Double = 0.07
    /// The orb's acceleration is clamped to this, in points per second squared.
    static let maxAcceleration: Double = 14_000

    /// The radius bodies are kept inside: the glass's inner surface.
    let innerRadius: Double
    let gravity: Double

    private(set) var bodies: [VaporBody] = []
    private(set) var particles: [VaporParticle] = []
    private(set) var isAsleep = true
    /// Total simulated time, for tests.
    private(set) var elapsed: Double = 0

    private var pendingSpawns: [PendingSpawn] = []
    private var random: VaporSeededRandom
    private var accumulator: Double = 0
    private var restTime: Double = 0
    private var quietTime: Double = 0
    private var motionTarget = SIMD2<Double>.zero
    private var motion = SIMD2<Double>.zero
    private var motionAge: Double = 0
    private var emitsParticles = true

    init(innerRadius: Double = Double(VaporGeometry.orbDiameter) / 2 - 3, seed: UInt64 = 0x5EED) {
        self.innerRadius = innerRadius
        gravity = 980 * innerRadius / 53
        random = VaporSeededRandom(seed: seed)
    }

    // MARK: Queries

    /// Whether the folder has a body in the pile, or one about to drop in.
    func contains(_ folderID: UUID) -> Bool {
        bodies.contains { $0.folderID == folderID && $0.isSettledMember }
            || pendingSpawns.contains { $0.folderID == folderID }
    }

    /// Folders with a body in the pile (not leaving), in body order.
    var memberIDs: [UUID] { bodies.filter(\.isSettledMember).map(\.folderID) }
    /// Folders whose staggered drop hasn't started yet. A folder taken out in that moment must
    /// cancel its drop too, or it would land in an orb that no longer holds it.
    var pendingSpawnIDs: [UUID] { pendingSpawns.map(\.folderID) }

    // MARK: Changes

    /// Adds a body for `folderID`, after `delay` seconds when given.
    mutating func spawn(_ folderID: UUID, radius: Double, style: SpawnStyle, delay: Double = 0) {
        guard !contains(folderID) else { return }
        wake()
        if delay > 0, style != .settled {
            pendingSpawns.append(PendingSpawn(folderID: folderID, radius: radius, style: style, delay: delay))
            return
        }
        spawnNow(folderID, radius: radius, style: style)
        if style == .settled { settle() }
    }

    /// Takes a folder's body out: a pop with sparks, or a fade under Reduce Motion.
    mutating func remove(_ folderID: UUID, delay: Double = 0, reduceMotion: Bool) {
        pendingSpawns.removeAll { $0.folderID == folderID }
        schedule([folderID], as: reduceMotion ? .fading : .popping, delay: delay, stagger: 0)
    }

    /// Evaporates the given folders' bodies, top first, one every ``evaporateStagger`` seconds,
    /// starting after `delay`. Under Reduce Motion they all fade together.
    mutating func evaporate(_ folderIDs: Set<UUID>, delay: Double = 0, reduceMotion: Bool) {
        pendingSpawns.removeAll { folderIDs.contains($0.folderID) }
        schedule(folderIDs, as: reduceMotion ? .fading : .evaporating, delay: delay,
                 stagger: reduceMotion ? 0 : Self.evaporateStagger)
    }

    /// Updates a body's size when its folder's measurement arrives.
    mutating func setBaseRadius(_ radius: Double, for folderID: UUID) {
        var changed = false
        for index in bodies.indices where bodies[index].folderID == folderID && bodies[index].state == .live
            && abs(bodies[index].baseRadius - radius) > 0.01 {
            bodies[index].baseRadius = radius
            changed = true
        }
        for index in pendingSpawns.indices where pendingSpawns[index].folderID == folderID {
            pendingSpawns[index].radius = radius
        }
        if changed { wake() }
    }

    /// The orb's acceleration while it's dragged (points per second squared, y down). The pile
    /// sloshes against it. Samples stop arriving when the pointer stops, so a sample older than
    /// 60 ms decays toward zero instead of pushing forever.
    mutating func setMotion(acceleration: SIMD2<Double>) {
        let limit = Self.maxAcceleration
        motionTarget = SIMD2(min(max(acceleration.x, -limit), limit), min(max(acceleration.y, -limit), limit))
        motionAge = 0
        let moving = (motionTarget * motionTarget).sum() > 1
        if moving, !bodies.isEmpty { wake() }
    }

    /// Runs the simulation silently until the pile rests (at most four simulated seconds), then
    /// stops every body. Used to place bodies already settled.
    mutating func settle() {
        let emitted = emitsParticles
        emitsParticles = false
        motionTarget = .zero
        motion = .zero
        wake()
        for _ in 0..<Int(4 / Self.substep) {
            step(Self.substep)
            if isAsleep { break }
        }
        emitsParticles = emitted
        particles.removeAll()
        fallAsleep()
    }

    // MARK: Time

    /// Integrates `seconds` of simulated time in fixed substeps. Does nothing while asleep.
    mutating func advance(by seconds: Double) {
        guard !isAsleep else { return }
        accumulator += min(max(seconds, 0), Self.maxFrame)
        while accumulator >= Self.substep {
            accumulator -= Self.substep
            step(Self.substep)
            if isAsleep { break }
        }
    }

    // MARK: Private

    private mutating func wake() {
        isAsleep = false
        restTime = 0
        quietTime = 0
    }

    private mutating func fallAsleep() {
        let fit = fitFactor()
        for index in bodies.indices where bodies[index].state == .live {
            bodies[index].velocity = .zero
            bodies[index].spin = 0
            bodies[index].radius = bodies[index].baseRadius * fit
            bodies[index].scale = 1
        }
        accumulator = 0
        isAsleep = pendingSpawns.isEmpty && particles.isEmpty && bodies.allSatisfy(\.isSettledMember)
    }

    private mutating func spawnNow(_ folderID: UUID, radius: Double, style: SpawnStyle) {
        let size = radius * fitFactor(adding: radius)
        let body = VaporBody(
            folderID: folderID,
            position: SIMD2(random.signed() * 6, -innerRadius + size + 1),
            velocity: SIMD2(random.signed() * 35, style == .restore ? 60 : 170),
            angle: random.signed() * 0.4, spin: random.signed() * 3,
            baseRadius: radius, radius: size,
            scale: style == .settled ? 1 : 0.25, alpha: 1)
        bodies.append(body)
    }

    private mutating func schedule(_ folderIDs: Set<UUID>, as state: VaporBody.State, delay: Double, stagger: Double) {
        // Top of the pile first, so the cloud lifts off from above.
        let targets = bodies.indices
            .filter { folderIDs.contains(bodies[$0].folderID) && bodies[$0].isSettledMember }
            .sorted { bodies[$0].position.y < bodies[$1].position.y }
        guard !targets.isEmpty else { return }
        wake()
        for (order, index) in targets.enumerated() {
            let wait = delay + Double(order) * stagger
            if wait <= 0 {
                begin(state, at: index)
            } else {
                bodies[index].scheduledState = state
                bodies[index].scheduleDelay = wait
            }
        }
    }

    private mutating func begin(_ state: VaporBody.State, at index: Int) {
        bodies[index].state = state
        bodies[index].scheduledState = nil
        switch state {
        case .evaporating:
            bodies[index].velocity = SIMD2(bodies[index].velocity.x * 0.3, -20)
        case .popping:
            guard emitsParticles else { break }
            for _ in 0..<8 { emitSpark(at: bodies[index].position) }
        case .live, .fading:
            break
        }
    }

    private func fitFactor(adding extra: Double? = nil) -> Double {
        var radii = bodies.filter { $0.state == .live }.map(\.baseRadius)
        if let extra { radii.append(extra) }
        return VaporPileSizing.fitScale(radii: radii, innerRadius: innerRadius)
    }

    private mutating func step(_ h: Double) {
        elapsed += h
        startDueSpawns(h)
        updateMotion(h)
        integrate(h)
        for pass in 0..<2 {
            collide(withImpulses: pass == 0)
            confine()
        }
        bodies.removeAll { $0.alpha <= 0 }
        updateParticles(h)
        updateSleep(h)
    }

    private mutating func startDueSpawns(_ h: Double) {
        guard !pendingSpawns.isEmpty else { return }
        for index in pendingSpawns.indices { pendingSpawns[index].delay -= h }
        let due = pendingSpawns.filter { $0.delay <= 0 }
        pendingSpawns.removeAll { $0.delay <= 0 }
        for spawn in due { spawnNow(spawn.folderID, radius: spawn.radius, style: spawn.style) }
    }

    private mutating func updateMotion(_ h: Double) {
        motionAge += h
        if motionAge > 0.06 { motionTarget *= exp(-h * 25) }
        motion += (motionTarget - motion) * min(1, h * 18)
    }

    private mutating func integrate(_ h: Double) {
        let fit = fitFactor()
        for index in bodies.indices {
            if bodies[index].scheduledState != nil {
                bodies[index].scheduleDelay -= h
                if bodies[index].scheduleDelay <= 0, let next = bodies[index].scheduledState { begin(next, at: index) }
            }
            var body = bodies[index]
            switch body.state {
            case .live:
                body.radius += (body.baseRadius * fit - body.radius) * min(1, h * 8)
                body.velocity.y += gravity * h
                // The contents lag behind the glass: accelerating the orb pushes them the other way.
                body.velocity -= motion * 0.32 * h
                body.scale += (1 - body.scale) * min(1, h * 9)
            case .evaporating:
                body.velocity.y -= 380 * h
                body.velocity.x *= 0.97
                body.alpha -= h * 1.45
                body.scale += h * 0.35
                body.spin *= 0.96
                if emitsParticles {
                    body.emitBudget += 60 * h
                    while body.emitBudget >= 1 {
                        body.emitBudget -= 1
                        emitSteam(near: body)
                    }
                }
            case .popping:
                body.scale += h * 2.6
                body.alpha -= h * 5.5
            case .fading:
                body.alpha -= h * 4
            }
            body.position += body.velocity * h
            body.angle += body.spin * h
            body.spin *= 0.985
            body.velocity *= 0.999
            bodies[index] = body
        }
    }

    /// Pushes overlapping live bodies apart. The first pass also exchanges momentum (a soft
    /// bounce) and turns tangential sliding into spin, which is what makes folders tumble.
    private mutating func collide(withImpulses: Bool) {
        let live = bodies.indices.filter { bodies[$0].state == .live }
        guard live.count > 1 else { return }
        for i in 0..<live.count {
            for j in (i + 1)..<live.count {
                var a = bodies[live[i]], c = bodies[live[j]]
                let delta = c.position - a.position
                let distance = (delta * delta).sum().squareRoot()
                let reach = a.radius + c.radius
                guard distance < reach else { continue }
                if distance < 1e-4 {
                    a.position.x -= 0.5
                    c.position.x += 0.5
                    bodies[live[i]] = a
                    bodies[live[j]] = c
                    continue
                }
                let normal = delta / distance
                let overlap = (reach - distance) / 2
                a.position -= normal * overlap
                c.position += normal * overlap
                if withImpulses {
                    let relative = ((c.velocity - a.velocity) * normal).sum()
                    if relative < 0 {
                        let impulse = -1.18 * relative / 2
                        a.velocity -= normal * impulse
                        c.velocity += normal * impulse
                        let tangent = SIMD2(-normal.y, normal.x)
                        let slide = ((c.velocity - a.velocity) * tangent).sum()
                        a.spin += slide * 0.025
                        c.spin -= slide * 0.025
                        a.velocity += tangent * (slide * 0.06)
                        c.velocity -= tangent * (slide * 0.06)
                    }
                    a.spin *= 0.97
                    c.spin *= 0.97
                }
                bodies[live[i]] = a
                bodies[live[j]] = c
            }
        }
    }

    /// Keeps live bodies inside the glass. A body may sink 10 % of its radius into the rim, since
    /// the drawn icon is not a full circle. Sliding along the glass spins the body and slows it.
    private mutating func confine() {
        for index in bodies.indices where bodies[index].state == .live {
            var body = bodies[index]
            let distance = (body.position * body.position).sum().squareRoot()
            let limit = innerRadius - body.radius * 0.9
            guard distance > limit, distance > 0 else { continue }
            let normal = body.position / distance
            body.position = normal * limit
            let outward = (body.velocity * normal).sum()
            if outward > 0 { body.velocity -= normal * (1.32 * outward) }
            let tangent = SIMD2(-normal.y, normal.x)
            let slide = (body.velocity * tangent).sum()
            body.spin += (slide / max(body.radius, 1) * 0.7 - body.spin) * 0.12
            body.velocity -= tangent * (slide * 0.035)
            bodies[index] = body
        }
    }

    private mutating func updateParticles(_ h: Double) {
        guard !particles.isEmpty else { return }
        for index in particles.indices {
            particles[index].life += h
            particles[index].position += particles[index].velocity * h
            switch particles[index].kind {
            case .steam:
                particles[index].velocity.x *= 0.985
                particles[index].radius += h * 2.2
            case .spark:
                particles[index].velocity *= 0.92
            }
        }
        particles.removeAll { $0.life >= $0.lifetime }
    }

    private mutating func updateSleep(_ h: Double) {
        let calm = pendingSpawns.isEmpty && particles.isEmpty && bodies.allSatisfy(\.isSettledMember)
            && (motion * motion).sum() < 1 && (motionTarget * motionTarget).sum() < 1
        guard calm else {
            restTime = 0
            quietTime = 0
            return
        }
        if bodies.isEmpty {
            fallAsleep()
            return
        }
        let fit = fitFactor()
        let speedLimit = Self.restSpeed * Self.restSpeed
        let resting = bodies.allSatisfy {
            ($0.velocity * $0.velocity).sum() < speedLimit && abs($0.spin) < 0.6
                && abs($0.radius - $0.baseRadius * fit) < 0.05 && $0.scale > 0.995
        }
        restTime = resting ? restTime + h : 0
        quietTime += h
        if restTime > Self.restDuration || quietTime > Self.quietLimit { fallAsleep() }
    }

    private mutating func emitSteam(near body: VaporBody) {
        let jitter = SIMD2(random.signed() * body.radius * 0.8, random.signed() * body.radius * 0.5)
        particles.append(VaporParticle(
            kind: .steam, position: body.position + jitter,
            velocity: SIMD2(random.signed() * 13, -random.value(in: 30...90)),
            radius: random.value(in: 0.8...2.4), lifetime: random.value(in: 0.7...1.2)))
    }

    private mutating func emitSpark(at position: SIMD2<Double>) {
        let angle = random.value(in: 0...(2 * .pi)), speed = random.value(in: 60...180)
        particles.append(VaporParticle(
            kind: .spark, position: position, velocity: SIMD2(cos(angle), sin(angle)) * speed,
            radius: random.value(in: 1...2), lifetime: random.value(in: 0.35...0.6)))
    }
}
