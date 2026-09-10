import Foundation

/// One pin's care timestamps. Mood is computed at read time from these clocks.
nonisolated struct DockSimsPet: Codable, Equatable, Sendable {
    var pinID: String
    var lastFedAt: Date
    var lastCheeredAt: Date

    var isValid: Bool {
        DockSimsLimits.isValidPinID(pinID)
            && lastFedAt.timeIntervalSince1970.isFinite
            && lastCheeredAt.timeIntervalSince1970.isFinite
    }

    /// Most recent care, used when the document has to drop the oldest pets.
    var lastCaredAt: Date { max(lastFedAt, lastCheeredAt) }
}

/// Value the overlay reads. Safe to recompute from a `TimelineView` clock without touching the store.
nonisolated struct DockSimsPinState: Equatable, Sendable {
    let pinID: String
    let lastFedAt: Date
    let lastCheeredAt: Date
    /// Normalized 0…1 animation strength (`intensity / 100`).
    let intensity: Double

    func hunger(at now: Date) -> Double {
        DockSimsLimits.hunger(since: lastFedAt, at: now)
    }

    func happiness(at now: Date) -> Double {
        DockSimsLimits.happiness(since: lastCheeredAt, at: now)
    }

    func mood(at now: Date) -> DockSimsMood {
        DockSimsMood.derive(hunger: hunger(at: now), happiness: happiness(at: now))
    }

    func idle(at now: Date) -> DockSimsIdle { mood(at: now).idle }
}

/// Versioned local-only Sims document. Nothing here is fetched or published.
///
/// `isEnabled` stays off until the user opts in. Disabling keeps pets so turning the feature
/// back on restores the same moods. `baselineAt` is the implicit last-care time for pins
/// that have never been fed, cheered, or settled.
nonisolated struct DockSimsDocument: Codable, Equatable, Sendable {
    var version: Int
    var isEnabled: Bool
    var intensity: Double
    var baselineAt: Date?
    var pets: [String: DockSimsPet]

    static let empty = DockSimsDocument(
        version: DockSimsLimits.version,
        isEnabled: false,
        intensity: DockSimsLimits.defaultIntensity,
        baselineAt: nil,
        pets: [:]
    )

    enum CodingKeys: String, CodingKey {
        case version, isEnabled, intensity, baselineAt, pets
    }

    init(version: Int = DockSimsLimits.version, isEnabled: Bool = false,
         intensity: Double = DockSimsLimits.defaultIntensity, baselineAt: Date? = nil,
         pets: [String: DockSimsPet] = [:]) {
        self.version = version
        self.isEnabled = isEnabled
        self.intensity = intensity
        self.baselineAt = baselineAt
        self.pets = pets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? DockSimsLimits.version
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        intensity = try container.decodeIfPresent(Double.self, forKey: .intensity)
            ?? DockSimsLimits.defaultIntensity
        baselineAt = try container.decodeIfPresent(Date.self, forKey: .baselineAt)
        pets = try container.decodeIfPresent([String: DockSimsPet].self, forKey: .pets) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(intensity, forKey: .intensity)
        try container.encodeIfPresent(baselineAt, forKey: .baselineAt)
        try container.encode(pets, forKey: .pets)
    }

    var isValid: Bool {
        version == DockSimsLimits.version
            && intensity.isFinite
            && DockSimsLimits.intensityRange.contains(intensity)
            && (baselineAt?.timeIntervalSince1970.isFinite ?? true)
            && pets.count <= DockSimsLimits.maximumPets
            && pets.allSatisfy { id, pet in
                id == pet.pinID && pet.isValid
            }
    }

    /// Pins without their own record inherit the baseline so a newly enabled dock starts playful
    /// and then drifts, instead of inventing a new "now" on every read.
    func clocks(for pinID: String, at now: Date) -> (fed: Date, cheered: Date)? {
        guard DockSimsLimits.isValidPinID(pinID) else { return nil }
        if let pet = pets[pinID] { return (pet.lastFedAt, pet.lastCheeredAt) }
        let baseline = baselineAt ?? now
        return (baseline, baseline)
    }
}
