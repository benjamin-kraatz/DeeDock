import Foundation

/// Optional decoration for the shared timer. Missing configuration keeps older documents unchanged.
nonisolated struct BossFightConfiguration: Codable, Equatable, Sendable {
    static let maximumPartySize = 8
    var enabled = false
    var party: [BossFightPartyMember] = []

    var isValid: Bool {
        party.count <= Self.maximumPartySize
            && Set(party.map(\.id)).count == party.count
            && party.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty && $0.id.count <= 512 && $0.name.count <= 512 }
    }
}

/// User-selected app identity and display name; no activity or window contents are retained.
nonisolated struct BossFightPartyMember: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
}
