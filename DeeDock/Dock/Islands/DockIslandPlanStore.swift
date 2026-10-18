import Foundation
import Observation

/// Reads and writes one display's island plan. Nil means the automatic arrangement.
struct DockIslandPlanRepository {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, displayID: String) {
        self.defaults = defaults
        key = "dock.islands.v1.\(displayID)"
    }

    func load() throws -> DockIslandPlan? {
        guard let object = defaults.object(forKey: key) else { return nil }
        guard let data = object as? Data else { throw CocoaError(.coderReadCorrupt) }
        return try JSONDecoder().decode(DockIslandPlan.self, from: data)
    }

    func save(_ plan: DockIslandPlan) throws {
        if plan == .automatic {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(try JSONEncoder().encode(plan), forKey: key)
        }
    }
}

/// Island plans for every display, shared by the docks and Settings.
///
/// Plans are per display, not per Dock Mode: switching modes keeps the island names and tints and
/// reconciles the pin counts against the new pin list. A plan that fails to decode falls back to
/// automatic for that display and is replaced by the next edit.
@MainActor @Observable
final class DockIslandPlanStore {
    private(set) var plans: [String: DockIslandPlan] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    /// Fired after a saved change, so docks re-project their islands.
    @ObservationIgnored var didChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// This display's plan, loading it on first use.
    func plan(for displayID: String) -> DockIslandPlan {
        if let plan = plans[displayID] { return plan }
        let plan = (try? DockIslandPlanRepository(defaults: defaults, displayID: displayID).load()) ?? .automatic
        plans[displayID] = plan
        return plan
    }

    /// Saves `plan` for `displayID` and notifies docks. Returns false when the write failed.
    @discardableResult
    func save(_ plan: DockIslandPlan, for displayID: String) -> Bool {
        guard plan != plans[displayID] else { return true }
        do {
            try DockIslandPlanRepository(defaults: defaults, displayID: displayID).save(plan)
        } catch {
            return false
        }
        plans[displayID] = plan
        didChange?()
        return true
    }
}
