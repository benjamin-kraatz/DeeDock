#if DEBUG
import Foundation

/// Scenarios contain only fictional identities and never read application or user state.
nonisolated enum LauncherSuggestionSyntheticScenario: String, CaseIterable, Codable, Identifiable, Sendable {
    case coldStart, routine, burst, conflicting, drift, unfamiliar
    var id: String { rawValue }
}

/// Reproducible controls for an isolated synthetic history. Strength controls outcomes;
/// noise independently perturbs input context, so neither knob encodes the eventual label.
nonisolated struct LauncherSuggestionSyntheticConfiguration: Codable, Equatable, Sendable {
    var scenario: LauncherSuggestionSyntheticScenario = .routine
    var exampleCount = 120
    var days = 14
    var patternStrength = 0.85
    var noise = 0.15
    var seed: UInt64 = 42
    var referenceDate = Date(timeIntervalSince1970: 1_788_868_800)

    var clamped: Self {
        var value = self
        value.exampleCount = min(1_000, max(0, exampleCount))
        value.days = min(90, max(1, days))
        value.patternStrength = patternStrength.isFinite ? min(1, max(0, patternStrength)) : 0.85
        value.noise = noise.isFinite ? min(1, max(0, noise)) : 0.15
        if !referenceDate.timeIntervalSince1970.isFinite {
            value.referenceDate = Self().referenceDate
        }
        return value
    }
}

/// Outcomes are generated before evaluation. A chronological replay predicts each future
/// example from its preceding context, then appends that outcome to its own isolated history.
nonisolated struct LauncherSuggestionSyntheticDataset: Sendable {
    let configuration: LauncherSuggestionSyntheticConfiguration
    let history: [LauncherSuggestionExample]
    let future: [LauncherSuggestionExample]
    let query: LauncherSuggestionContext
    let expectedTargetID: String
    /// First future outcome governed by the replacement pattern, or nil without drift.
    let driftIndex: Int?
    /// Dominant outcome after the drift, separate from incidental noisy future labels.
    let driftTargetID: String?
}

/// Pure deterministic synthetic data. Cold start respects the requested count (the UI can
/// preset five). Routine repeats a daily pattern; burst compresses evidence into one UTC day;
/// conflicting distributes its usual pattern among three outcomes; drift changes its dominant
/// outcome at future index zero; unfamiliar changes query inputs while retaining old history.
nonisolated enum LauncherSuggestionSyntheticGenerator {
    static func generate(_ configuration: LauncherSuggestionSyntheticConfiguration) -> LauncherSuggestionSyntheticDataset {
        let configuration = configuration.clamped
        var random = Generator(seed: configuration.seed)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let endDay = calendar.startOfDay(for: configuration.referenceDate)
        let historyDays = configuration.scenario == .burst ? 1 : configuration.days
        var history: [LauncherSuggestionExample] = []
        var previousDay = -1
        var positionInDay = 0
        for index in 0..<configuration.exampleCount {
            let day = index * historyDays / max(1, configuration.exampleCount)
            if day == previousDay { positionInDay += 1 } else { positionInDay = 0; previousDay = day }
            // Up to 1,000 samples occupy less than one hour. Every historical outcome precedes
            // referenceDate, including a reference at UTC midnight, and dates strictly increase.
            let date = endDay.addingTimeInterval(Double(day - historyDays) * 86_400 + 36_000 + Double(positionInDay) * 3)
            history.append(example(date: date, future: false, configuration: configuration,
                                   calendar: calendar, random: &random))
        }
        let future = (0..<60).map { index in
            let date = configuration.referenceDate.addingTimeInterval(Double(index / 4) * 86_400 + Double(index % 4) * 300)
            return example(date: date, future: true, configuration: configuration, calendar: calendar, random: &random)
        }
        return .init(configuration: configuration, history: history, future: future,
                     query: future[0].context, expectedTargetID: future[0].targetID,
                     driftIndex: configuration.scenario == .drift ? 0 : nil,
                     driftTargetID: configuration.scenario == .drift ? "synthetic.browser" : nil)
    }

    private static func example(date: Date, future: Bool, configuration: LauncherSuggestionSyntheticConfiguration,
                                calendar: Calendar, random: inout Generator) -> LauncherSuggestionExample {
        let unfamiliar = future && configuration.scenario == .unfamiliar
        let noisy = random.unit() < configuration.noise
        let source = unfamiliar ? "synthetic.calendar" : noisy ? "synthetic.notes" : "synthetic.editor"
        let contextDate = date.addingTimeInterval(-1)
        let context = LauncherSuggestionContext(date: contextDate, foregroundID: source,
            modeID: unfamiliar ? "synthetic.personal" : noisy ? "synthetic.research" : "synthetic.work",
            recentIDs: unfamiliar ? ["synthetic.mail", "synthetic.calendar"] : noisy ? ["synthetic.browser"] : ["synthetic.editor"],
            runningIDs: unfamiliar ? ["synthetic.mail", "synthetic.calendar"] : ["synthetic.editor", "synthetic.browser", "synthetic.terminal"],
            hour: calendar.component(.hour, from: contextDate), weekday: calendar.component(.weekday, from: contextDate))
        let followsPattern = random.unit() < configuration.patternStrength
        // Consume the same draws at every strength/noise setting so context perturbations
        // remain independent of changes to the outcome probability.
        let outcomeChoice = random.next()
        let target: String
        if configuration.scenario == .conflicting && followsPattern {
            target = ["synthetic.terminal", "synthetic.browser", "synthetic.simulator"][Int(outcomeChoice % 3)]
        } else {
            let dominant = future && configuration.scenario == .drift ? "synthetic.browser" : "synthetic.terminal"
            let alternatives = ["synthetic.terminal", "synthetic.browser", "synthetic.simulator", "synthetic.mail", "synthetic.calendar"]
                .filter { $0 != dominant && $0 != source }
            target = followsPattern ? dominant : alternatives[Int(outcomeChoice % UInt64(alternatives.count))]
        }
        return .init(id: random.uuid(), context: context, targetID: target, date: date)
    }

    /// SplitMix64 supplies both draws and UUID bytes. No process randomness or wall clock enters
    /// generation; wrapping arithmetic also makes seeds at UInt64.max well-defined.
    private struct Generator {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
            value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
            return value ^ (value >> 31)
        }
        mutating func unit() -> Double { Double(next() >> 11) / 9_007_199_254_740_992 }
        mutating func uuid() -> UUID {
            let first = next(), second = next()
            var bytes = (0..<8).map { UInt8(truncatingIfNeeded: first >> ($0 * 8)) }
            bytes += (0..<8).map { UInt8(truncatingIfNeeded: second >> ($0 * 8)) }
            bytes[6] = (bytes[6] & 0x0F) | 0x40
            bytes[8] = (bytes[8] & 0x3F) | 0x80
            return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                               bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        }
    }
}
#endif
