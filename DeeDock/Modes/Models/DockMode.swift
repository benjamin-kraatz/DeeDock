import Foundation

/// One display's mode-owned pin arrangement and optional visibility override.
struct DockModeDisplayConfiguration: Codable, Equatable {
    var pins: [DockPin]
    var appVisibility: DockAppVisibility?
}

/// A named configuration applied to every display in one switch.
struct DockMode: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var appVisibility: DockAppVisibility
    var displays: [String: DockModeDisplayConfiguration]

    init(id: UUID = UUID(), name: String, appVisibility: DockAppVisibility = .showAll,
         displays: [String: DockModeDisplayConfiguration] = [:]) {
        self.id = id
        self.name = name
        self.appVisibility = appVisibility
        self.displays = displays
    }
}

/// Versioned, atomically persisted Dock Modes state.
struct DockModesDocument: Codable, Equatable {
    static let currentVersion = 1

    var version = currentVersion
    var modes: [DockMode]
    var activeModeID: UUID
    var previousModeID: UUID?

    var activeMode: DockMode? { modes.first { $0.id == activeModeID } }
    var previousMode: DockMode? { previousModeID.flatMap { id in modes.first { $0.id == id } } }

    /// Rejects partial or ambiguous documents before they can replace live dock state.
    var isValid: Bool {
        guard version == Self.currentVersion, !modes.isEmpty,
              modes.contains(where: { $0.id == activeModeID }) else { return false }
        let ids = modes.map(\.id)
        guard Set(ids).count == ids.count else { return false }
        let names = modes.map { DockModeNaming.comparisonKey($0.name) }
        guard names.allSatisfy({ !$0.isEmpty }), Set(names).count == names.count else { return false }
        if let previousModeID {
            guard previousModeID != activeModeID, modes.contains(where: { $0.id == previousModeID }) else { return false }
        }
        return modes.allSatisfy { mode in
            mode.displays.allSatisfy { id, configuration in
                id.hasPrefix("display.") && DockPinEditing.unique(configuration.pins) == configuration.pins
            }
        }
    }
}

enum DockModeNaming {
    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func comparisonKey(_ name: String) -> String {
        normalized(name).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    static func isAvailable(_ name: String, in modes: [DockMode], excluding id: UUID? = nil) -> Bool {
        let key = comparisonKey(name)
        return !key.isEmpty && !modes.contains { $0.id != id && comparisonKey($0.name) == key }
    }

    static func copyName(for source: String, in modes: [DockMode]) -> String {
        let base = String(localized: .dockModeCopyName(modeName: source))
        if isAvailable(base, in: modes) { return base }
        var index = 2
        while !isAvailable("\(base) \(index)", in: modes) { index += 1 }
        return "\(base) \(index)"
    }
}
