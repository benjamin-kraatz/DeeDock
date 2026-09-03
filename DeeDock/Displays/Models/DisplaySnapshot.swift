import Foundation
import CoreGraphics

/// One online display. Persistent identity is independent of the current numeric display handle.
struct DisplaySnapshot: Identifiable, Equatable {
    let id: String
    let runtimeID: UInt32
    let name: String
    let isPersistent: Bool
    let isPrimary: Bool
    let frame: CGRect
    let visibleFrame: CGRect
    let mirrorSource: UInt32?
    let isDrawable: Bool

    /// Only the source of a mirrored desktop owns a panel.
    var hostsDock: Bool { isDrawable && mirrorSource == nil }
}

/// Rejects duplicate/missing UUIDs without conflating their saved profiles.
/// Ambiguity is latched until disconnect; session keys cannot overwrite persistent preferences.
struct DisplayIdentityResolver {
    private var sessions: [UInt32: String] = [:]
    private var ambiguous: Set<UInt32> = []

    mutating func resolve(_ identities: [UInt32: String?]) -> [UInt32: String] {
        let connected = Set(identities.keys)
        sessions = sessions.filter { connected.contains($0.key) }
        ambiguous.formIntersection(connected)
        let counts = Dictionary(grouping: identities.values.compactMap { $0 }, by: { $0 }).mapValues(\.count)
        for (id, uuid) in identities where uuid == nil || counts[uuid ?? "", default: 0] > 1 {
            ambiguous.insert(id)
        }
        return identities.reduce(into: [:]) { result, pair in
            if ambiguous.contains(pair.key) {
                if sessions[pair.key] == nil { sessions[pair.key] = "session.\(UUID().uuidString)" }
                result[pair.key] = sessions[pair.key]
            } else if let uuid = pair.value { result[pair.key] = "display.\(uuid)" }
        }
    }
}

/// Pure selection policy shared by reconciliation, Settings ordering, and keyboard focus.
enum DisplayPolicy {
    static func ordered(_ displays: [DisplaySnapshot]) -> [DisplaySnapshot] {
        displays.sorted {
            if $0.isPrimary != $1.isPrimary { return $0.isPrimary }
            if $0.frame.minX != $1.frame.minX { return $0.frame.minX < $1.frame.minX }
            if $0.frame.minY != $1.frame.minY { return $0.frame.minY < $1.frame.minY }
            return $0.id < $1.id
        }
    }

    static func enabled(_ displays: [DisplaySnapshot], isEnabled: (String) -> Bool) -> [DisplaySnapshot] {
        ordered(displays).filter { $0.hostsDock && isEnabled($0.id) }
    }

    static func focusTarget(displays: [DisplaySnapshot], pointer: CGPoint) -> String? {
        let ordered = ordered(displays)
        return ordered.first(where: { $0.frame.contains(pointer) })?.id ?? ordered.first?.id
    }
}
