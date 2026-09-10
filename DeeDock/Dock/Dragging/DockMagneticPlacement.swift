import Foundation
import CoreGraphics

/// A pin or folder stack parked on the desktop after a magnetized drop.
///
/// Coordinates are AppKit screen points and may be negative. The pin stays in the
/// display's saved list; this record only says it is not drawn in the linear dock.
nonisolated struct DockMagneticPlacement: Codable, Equatable, Sendable {
    var pinID: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    init(pinID: String, frame: CGRect) {
        self.pinID = pinID
        self.x = frame.origin.x
        self.y = frame.origin.y
        self.width = frame.size.width
        self.height = frame.size.height
    }
}

/// Per-display parked pins. Missing keys mean the pin still lives only on the dock.
@MainActor
final class DockMagneticPlacementStore {
    private let defaults: UserDefaults
    private var cache: [String: [String: DockMagneticPlacement]] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func placements(for displayID: String) -> [DockMagneticPlacement] {
        Array(loaded(displayID).values)
    }

    func placedIDs(for displayID: String) -> Set<String> {
        Set(loaded(displayID).keys)
    }

    func frames(for displayID: String, excluding pinID: String?) -> [CGRect] {
        loaded(displayID).values.compactMap { placement in
            placement.pinID == pinID ? nil : placement.frame
        }
    }

    func place(_ placement: DockMagneticPlacement, on displayID: String) {
        var values = loaded(displayID)
        values[placement.pinID] = placement
        save(values, on: displayID)
    }

    func clear(pinID: String, on displayID: String) {
        var values = loaded(displayID)
        guard values.removeValue(forKey: pinID) != nil else { return }
        save(values, on: displayID)
    }

    /// Drops records whose pins are no longer saved on that display.
    func retain(pinIDs: Set<String>, on displayID: String) {
        let values = loaded(displayID).filter { pinIDs.contains($0.key) }
        guard values.count != loaded(displayID).count else { return }
        save(values, on: displayID)
    }

    private func key(_ displayID: String) -> String { "dock.magneticPlacements.v1.\(displayID)" }

    private func loaded(_ displayID: String) -> [String: DockMagneticPlacement] {
        if let cached = cache[displayID] { return cached }
        guard let data = defaults.data(forKey: key(displayID)),
              let decoded = try? JSONDecoder().decode([String: DockMagneticPlacement].self, from: data) else {
            cache[displayID] = [:]
            return [:]
        }
        cache[displayID] = decoded
        return decoded
    }

    private func save(_ values: [String: DockMagneticPlacement], on displayID: String) {
        cache[displayID] = values
        if values.isEmpty {
            defaults.removeObject(forKey: key(displayID))
        } else if let data = try? JSONEncoder().encode(values) {
            defaults.set(data, forKey: key(displayID))
        }
    }
}
