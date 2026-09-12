import Foundation

/// A one-hop cable. IDs resolve against the current mode's pins at execution time.
nonisolated struct PatchBayCable: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let displayID: String
    let modeID: UUID
    let appID: String
    let folderID: String
    let appName: String
    let folderName: String
}

/// Versioned, bounded routing preferences. No run state or file bookmarks are copied here.
nonisolated struct PatchBayDocument: Codable, Equatable, Sendable {
    static let maximumCables = 8
    var version = 1
    var enabled = false
    var cables: [PatchBayCable] = []

    var isValid: Bool {
        guard version == 1, cables.count <= Self.maximumCables,
              Set(cables.map(\.id)).count == cables.count else { return false }
        for cable in cables {
            guard [cable.displayID, cable.appID, cable.folderID, cable.appName, cable.folderName]
                .allSatisfy({ !$0.isEmpty && $0.utf8.count <= 1024 }) else { return false }
            guard cables.filter({ $0.displayID == cable.displayID && $0.modeID == cable.modeID
                && $0.appID == cable.appID }).count == 1 else { return false }
        }
        return true
    }
}

