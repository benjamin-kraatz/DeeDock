import Foundation

/// How a pin feels right now. Derived from care timestamps, never stored on its own.
///
/// Hungry wins over lonely when both needs are high, so a pin that has not been fed
/// does not look merely neglected. Playful is the fresh-care state: just fed and cheered.
nonisolated enum DockSimsMood: String, CaseIterable, Equatable, Sendable {
    case playful
    case content
    case hungry
    case lonely

    /// Idle motion that belongs with this mood. Views animate the overlay, not the app icon.
    var idle: DockSimsIdle {
        switch self {
        case .playful: .bounce
        case .content: .breathe
        case .hungry, .lonely: .sway
        }
    }

    /// SF Symbol drawn as the mood mark. Kept on the model so previews and tests share one map.
    var symbolName: String {
        switch self {
        case .playful: "face.smiling"
        case .content: "heart.fill"
        case .hungry: "leaf.fill"
        case .lonely: "cloud"
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .playful: .simsMoodPlayful
        case .content: .simsMoodContent
        case .hungry: .simsMoodHungry
        case .lonely: .simsMoodLonely
        }
    }

    /// Maps hunger (0 just fed … 1 starving) and happiness (1 just cheered … 0 neglected).
    static func derive(hunger: Double, happiness: Double) -> DockSimsMood {
        if hunger >= DockSimsLimits.hungryThreshold { return .hungry }
        if happiness <= DockSimsLimits.lonelyThreshold { return .lonely }
        if hunger <= DockSimsLimits.playfulHunger,
           happiness >= DockSimsLimits.playfulHappiness {
            return .playful
        }
        return .content
    }
}

/// Small overlay motion. Intensity scales amplitude only; the style comes from the mood.
nonisolated enum DockSimsIdle: String, CaseIterable, Equatable, Sendable {
    case bounce
    case breathe
    case sway
}

/// Light care actions. Settle undoes Feed and Cheer on that pin without turning Sims off.
nonisolated enum DockSimsCareAction: String, CaseIterable, Equatable, Sendable {
    case feed
    case cheer
    case settle

    var title: LocalizedStringResource {
        switch self {
        case .feed: .simsFeed
        case .cheer: .simsCheer
        case .settle: .simsSettle
        }
    }

    var symbolName: String {
        switch self {
        case .feed: "leaf.fill"
        case .cheer: "heart.fill"
        case .settle: "moon.fill"
        }
    }
}

/// Shared bounds for the local Sims document and the care-loop clock.
enum DockSimsLimits {
    static let version = 1
    static let maximumPets = 256
    static let maximumPinIDLength = 4096
    static let maximumEncodedBytes = 256 * 1024
    /// Hours without a feed before a pin is fully hungry.
    static let hungerPeriod: TimeInterval = 6 * 3_600
    /// Hours without a cheer before a pin is fully lonely.
    static let lonelyPeriod: TimeInterval = 8 * 3_600
    static let hungryThreshold = 0.70
    static let lonelyThreshold = 0.30
    static let playfulHunger = 0.30
    static let playfulHappiness = 0.70
    /// Percent, matching other Features sliders. 15 keeps a trace of motion at the low end.
    static let defaultIntensity = 55.0
    static let intensityRange = 15.0...100.0
    static let intensityStep = 5.0
    static let storageKey = "dock.sims.v1"
    /// Debug clock steps. Not persisted; Release builds never expose them.
    static let debugHour: TimeInterval = 3_600
    static let debugTwoHours: TimeInterval = 2 * 3_600
    static let debugHungryStep: TimeInterval = hungerPeriod
    static let debugLonelyStep: TimeInterval = lonelyPeriod

    static func clampIntensity(_ value: Double) -> Double {
        let stepped = (value / intensityStep).rounded() * intensityStep
        return min(max(stepped, intensityRange.lowerBound), intensityRange.upperBound)
    }

    static func isValidPinID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= maximumPinIDLength
    }

    /// 0 just fed … 1 starving. Future timestamps do not produce negative hunger.
    static func hunger(since lastFedAt: Date, at now: Date) -> Double {
        progress(since: lastFedAt, at: now, period: hungerPeriod)
    }

    /// 1 just cheered … 0 neglected.
    static func happiness(since lastCheeredAt: Date, at now: Date) -> Double {
        1 - progress(since: lastCheeredAt, at: now, period: lonelyPeriod)
    }

    private static func progress(since start: Date, at now: Date, period: TimeInterval) -> Double {
        let elapsed = now.timeIntervalSince(start)
        guard elapsed.isFinite, period > 0 else { return 0 }
        if elapsed <= 0 { return 0 }
        return min(1, elapsed / period)
    }
}
