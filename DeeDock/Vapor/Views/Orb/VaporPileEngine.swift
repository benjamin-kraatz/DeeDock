import Foundation
import Observation

/// Drives ``VaporPhysicsWorld`` for the orb view: keeps one body per folder in the orb, turns
/// the controller's events into spawns, pops and evaporation, and steps the world once per
/// frame of the orb's `TimelineView`.
///
/// ``isRunning`` is the only observed property; the orb's timeline is paused whenever it is
/// false, so a settled pile costs nothing. The world itself is not observed: the canvas reads
/// it while drawing.
///
/// Main-actor isolated. Owned by the orb view (or injected for previews and snapshots).
@MainActor @Observable
final class VaporPileEngine {
    /// Whether the world is awake and the timeline should tick.
    private(set) var isRunning = false

    @ObservationIgnored private(set) var world: VaporPhysicsWorld
    @ObservationIgnored private var lastDate: Date?
    @ObservationIgnored private var hasSynced = false
    @ObservationIgnored private var handledAddition: UUID?
    @ObservationIgnored private var handledDeletion: UUID?
    /// Folders evaporating while staging runs. They stay in the controller until staging ends,
    /// and must not be respawned meanwhile.
    @ObservationIgnored private var leaving: Set<UUID> = []
    /// Bumped by every wake, so a deferred "fell asleep" from an older frame is ignored.
    @ObservationIgnored private var wakeGeneration = 0

    init(seed: UInt64 = 0x5EED) {
        world = VaporPhysicsWorld(seed: seed)
    }

    /// Brings the pile in line with the controller.
    ///
    /// - A new deletion evaporates its folders (after the rows have flown in from the panel).
    /// - Folders without a body drop in: with the pop for a new addition, gently for Undo, and
    ///   already settled on the first sync (launch) or under Reduce Motion.
    /// - Bodies whose folder left without a deletion pop (or fade), one after another for Clear.
    /// - Every body's size follows its folder's measurement.
    func sync(folders: [VaporFolder], addition: VaporEvent<VaporAddition>?, deletion: VaporEvent<VaporDeletion>?,
              isStaging: Bool, reduceMotion: Bool) {
        if let deletion, deletion.token != handledDeletion {
            handledDeletion = deletion.token
            let ids = Set(deletion.payload.folderIDs)
            leaving.formUnion(ids)
            let delay = reduceMotion ? 0 : VaporMotion.evaporateDelay(rows: ids.count, fromPanel: deletion.payload.fromPanel)
            world.evaporate(ids, delay: delay, reduceMotion: reduceMotion)
        }
        // Folders that failed to stage stay in the orb: once staging ends they drop back in.
        if !isStaging { leaving.removeAll() }

        var newAddition: VaporAddition?
        if let addition, addition.token != handledAddition {
            handledAddition = addition.token
            newAddition = addition.payload
        }

        let present = Set(folders.map(\.id))
        var removed = 0
        for id in world.memberIDs + world.pendingSpawnIDs where !present.contains(id) && !leaving.contains(id) {
            world.remove(id, delay: reduceMotion ? 0 : Double(removed) * 0.06, reduceMotion: reduceMotion)
            removed += 1
        }

        var dropped = 0
        for folder in folders where !world.contains(folder.id) && !leaving.contains(folder.id) {
            let radius = VaporPileSizing.radius(for: folder.measurement)
            if !hasSynced || reduceMotion {
                world.spawn(folder.id, radius: radius, style: .settled)
                continue
            }
            let restoring = newAddition?.source == .restore && newAddition?.folderIDs.contains(folder.id) == true
            let delay = restoring ? 0.12 + Double(dropped) * 0.08 : Double(dropped) * 0.09
            world.spawn(folder.id, radius: radius, style: restoring ? .restore : .drop, delay: delay)
            dropped += 1
        }
        for folder in folders {
            world.setBaseRadius(VaporPileSizing.radius(for: folder.measurement), for: folder.id)
        }
        hasSynced = true
        updateRunning()
    }

    /// Passes the orb's drag acceleration to the pile for the slosh. Ignored under Reduce Motion.
    func setMotion(_ motion: VaporOrbMotion, reduceMotion: Bool) {
        guard !reduceMotion else { return }
        world.setMotion(acceleration: SIMD2(Double(motion.acceleration.dx), Double(motion.acceleration.dy)))
        updateRunning()
    }

    /// Steps the world to `date` and returns it for drawing. Called from the canvas renderer,
    /// so it never changes observed state synchronously: falling asleep is published on the
    /// next main-actor turn, and only if nothing woke the world in between.
    func frame(at date: Date) -> VaporPhysicsWorld {
        let elapsed = lastDate.map { date.timeIntervalSince($0) } ?? (1.0 / 60)
        lastDate = date
        world.advance(by: elapsed)
        if world.isAsleep, isRunning {
            let generation = wakeGeneration
            Task { @MainActor [weak self] in
                guard let self, self.wakeGeneration == generation, self.world.isAsleep else { return }
                self.isRunning = false
                self.lastDate = nil
            }
        }
        return world
    }

    private func updateRunning() {
        guard !world.isAsleep else { return }
        wakeGeneration &+= 1
        if !isRunning {
            // The timeline was paused; don't integrate the paused gap.
            lastDate = nil
            isRunning = true
        }
    }
}
