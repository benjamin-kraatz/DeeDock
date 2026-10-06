import Foundation

/// The `com.apple.dock` preferences DOKK changes to tuck the macOS Dock away.
///
/// These keys are undocumented. The Dock reads them only when it starts, so every change ends
/// with a Dock restart.
enum SystemDockKey: String, CaseIterable, Codable {
    case autohide
    case autohideDelay = "autohide-delay"
    case tileSize = "tilesize"
    case orientation
}

/// The side the macOS Dock moves to while tucked away. The Dock has no top position.
enum SystemDockOrientation: String, Codable, Equatable {
    case left, right

    /// Left, unless DOKK's dock on the main display already sits on the left edge.
    ///
    /// - Parameter edge: DOKK's resolved edge on the main display, or nil when the main display
    ///   shows no DOKK dock.
    static func avoiding(_ edge: DockEdge?) -> SystemDockOrientation {
        edge == .left ? .right : .left
    }
}

/// A value DOKK writes into the Dock's preferences.
///
/// Comparison is semantic rather than by stored type: macOS writes `autohide` as a boolean or
/// as `1`, and `tilesize` as an integer or a real, depending on who wrote it last.
enum SystemDockValue: Equatable {
    case bool(Bool)
    case number(Double)
    case integer(Int)
    case string(String)

    /// The property-list object handed to CFPreferences.
    var propertyList: Any {
        switch self {
        case .bool(let value): value
        case .number(let value): value
        case .integer(let value): value
        case .string(let value): value
        }
    }

    /// Whether a value read from CFPreferences means the same thing as this one.
    func matches(_ stored: Any?) -> Bool {
        switch self {
        case .bool(let value):
            return (stored as? NSNumber)?.boolValue == value
        case .number(let value):
            return (stored as? NSNumber)?.doubleValue == value
        case .integer(let value):
            return (stored as? NSNumber)?.doubleValue == Double(value)
        case .string(let value):
            return (stored as? String) == value
        }
    }
}

/// What tucked away means: hidden, slow to reveal, as small as macOS allows, and on the side
/// away from DOKK.
enum SystemDockTuckPlan {
    /// Ten seconds keeps the Dock from appearing by accident while leaving it reachable by
    /// hovering, even when DOKK is not running to restore it.
    static let revealDelay: Double = 10
    /// The smallest tile size the macOS Dock accepts.
    static let tileSize = 16

    static func value(for key: SystemDockKey, orientation: SystemDockOrientation) -> SystemDockValue {
        switch key {
        case .autohide: .bool(true)
        case .autohideDelay: .number(revealDelay)
        case .tileSize: .integer(tileSize)
        case .orientation: .string(orientation.rawValue)
        }
    }
}

/// The values a person had before DOKK changed anything, kept until a restore succeeds.
///
/// Each previous value is archived as property-list data so a restore writes back the exact
/// stored type. A key without an entry did not exist, and restoring deletes it so macOS falls
/// back to its own default.
struct SystemDockSnapshot: Codable, Equatable {
    var originals: [String: Data]
    /// The orientation DOKK last wrote; with the plan it identifies every value DOKK wrote.
    var orientation: SystemDockOrientation

    /// Archives a value read from CFPreferences. Nil stays nil; a value that cannot be archived
    /// throws, so DOKK never writes over something it could not put back.
    static func archive(_ value: Any?) throws -> Data? {
        guard let value else { return nil }
        // Wrapped in an array because a property list's root has to be a container.
        return try PropertyListSerialization.data(fromPropertyList: [value], format: .binary, options: 0)
    }

    /// The previous value for `key`, or nil when it was absent or its archive is unreadable.
    func original(for key: SystemDockKey) -> Any? {
        guard let data = originals[key.rawValue],
              let array = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [Any]
        else { return nil }
        return array.first
    }
}

/// DOKK's persisted record of the switch and of what it changed.
struct SystemDockTuckRecord: Codable, Equatable {
    /// The person's choice. It stays on across quits; each launch tucks the Dock away again.
    var isOn = false
    /// Present from just before the first write until a restore succeeds, including across a
    /// crash, so a later launch can still put the person's values back.
    var snapshot: SystemDockSnapshot?
}
