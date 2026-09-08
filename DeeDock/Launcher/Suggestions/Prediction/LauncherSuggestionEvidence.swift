import Foundation

/// Shared abstention policy. Neighbor reconstruction supplies explicit evidence gates for
/// both engines; it is not represented as an internal Core ML trace or calibrated confidence.
nonisolated enum LauncherSuggestionEvidence {
    static func retainedExamples(document: LauncherSuggestionDocument, excluded: Set<String>,
                                 now: Date) -> [LauncherSuggestionExample] {
        let cutoff = now.addingTimeInterval(-LauncherSuggestionDocument.retention)
        return Array(document.examples.filter {
            $0.date > cutoff && $0.date <= now && $0.context.date > cutoff && $0.context.date <= now
                && !excluded.contains($0.targetID)
        }.suffix(10_000))
    }

    static func evaluate(engine: LauncherSuggestionEngine, raw: [String: Double], context: LauncherSuggestionContext,
                         document: LauncherSuggestionDocument, excluded: Set<String>, now: Date,
                         tuning: LauncherSuggestionTuning, elapsedMilliseconds: Double = 0) -> LauncherSuggestionEvaluation {
        let tuning = tuning.clamped
        let examples = retainedExamples(document: document, excluded: excluded, now: now)
        let neighbors = nearest(context: context, examples: examples, count: tuning.neighbors)
        // Explicit reconstruction policy: inverse squared distance, with a finite floor for
        // exact matches. This agreement is independent of engine votes and ranking bonuses.
        func weight(_ neighbor: LauncherSuggestionNeighbor) -> Double { 1 / max(neighbor.distance, 0.000001) }
        let totalWeight = neighbors.reduce(0) { $0 + weight($1) }
        let nearby = neighbors.filter { $0.distance <= tuning.maxDistance }
        let age = ageFactors(examples: examples, now: now)
        let decayed = raw.mapValues { $0.isFinite && $0 > 0 ? $0 : 0 }.reduce(into: [String: Double]()) { result, item in
            guard item.key != "__no_suggestion__" else { return }
            result[item.key] = item.value * (engine == .coreML ? age[item.key, default: 0] : 1)
        }
        let filtered = decayed.filter { $0.value > 0 && !excluded.contains($0.key) && $0.key != context.foregroundID }
        let maximum = max(filtered.values.max() ?? 1, 0.001)
        let beforeFeedback = LauncherSuggestionRanking.adjust(decayed, context: context, feedback: [], excluded: excluded, now: now)
        let adjusted = LauncherSuggestionRanking.adjust(decayed, context: context, feedback: document.feedback, excluded: excluded, now: now, includeNonPositive: true)
        // Include feedback-only and excluded candidates in diagnostics, but never allow a
        // bonus to manufacture supporting evidence for an app the predictor did not score.
        let ids = Set(raw.keys).union(adjusted.keys).union(document.examples.suffix(10_000).map(\.targetID))
            .subtracting(["__no_suggestion__"])
        let candidates: [LauncherSuggestionCandidateEvidence] = ids.map { id -> LauncherSuggestionCandidateEvidence in
            let supporting = nearby.filter { $0.appID == id }
            let days = Set(supporting.map { Int(floor($0.date.timeIntervalSince1970 / 86_400)) }).count
            let agreement = totalWeight > 0 ? supporting.reduce(0) { $0 + weight($1) } / totalWeight : 0
            let distance = neighbors.first(where: { $0.appID == id })?.distance
            let scored = filtered[id] != nil
            let normalized = scored ? filtered[id, default: 0] / maximum : 0
            let recency: Double = scored ? (context.secondsSinceUse[id].map { 0.1 * exp(-max(0, $0) / 3600) } ?? 0) : 0
            let running: Double = scored && context.runningIDs.contains(id) ? 0.025 : 0
            let final = adjusted[id, default: 0]
            var reasons: [LauncherSuggestionGateReason] = []
            if examples.count < tuning.minHistory { reasons.append(.history) }
            if supporting.count < tuning.minSupport { reasons.append(.support) }
            if days < tuning.minDays { reasons.append(.days) }
            if agreement < tuning.minAgreement { reasons.append(.agreement) }
            if distance == nil || distance! > tuning.maxDistance { reasons.append(.distance) }
            if excluded.contains(id) { reasons.append(.excluded) }
            if id == context.foregroundID { reasons.append(.foreground) }
            if !raw[id, default: 0].isFinite || raw[id, default: 0] <= 0 || final <= 0 { reasons.append(.nonPositive) }
            let rawScore: Double = raw[id, default: 0]
            let ageFactor: Double = engine == .coreML ? age[id, default: 0] : 1
            let feedbackAdjustment: Double = final - beforeFeedback[id, default: 0]
            return LauncherSuggestionCandidateEvidence(id: id, rawScore: rawScore, ageFactor: ageFactor,
                         normalizedScore: normalized, recencyBonus: recency, runningBonus: running,
                         feedbackAdjustment: feedbackAdjustment, finalScore: final,
                         support: supporting.count, distinctDays: days, agreement: agreement,
                         nearestDistance: distance, reasons: reasons)
        }
        let sorted = candidates.sorted { $0.finalScore == $1.finalScore ? $0.id < $1.id : $0.finalScore > $1.finalScore }
        return .init(engine: engine, candidates: sorted, neighbors: neighbors, elapsedMilliseconds: elapsedMilliseconds)
    }

    /// Computes deterministic nearest examples in the exact Float32 feature representation.
    /// Equal distances use app identity, date, then persistent example identity as tie breakers.
    static func nearest(context: LauncherSuggestionContext, examples: [LauncherSuggestionExample],
                        count: Int) -> [LauncherSuggestionNeighbor] {
        let input = context.featureVector
        return Array(examples.map { example in
            let vector = example.context.featureVector
            let distance = zip(input, vector).reduce(0.0) { result, pair in
                let difference = Double(pair.0) - Double(pair.1)
                return result + difference * difference
            }
            return LauncherSuggestionNeighbor(id: example.id, appID: example.targetID, date: example.date,
                                              distance: distance, context: example.context)
        }.sorted {
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            if $0.appID != $1.appID { return $0.appID < $1.appID }
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.id.uuidString < $1.id.uuidString
        }.prefix(max(1, count)))
    }

    private static func ageFactors(examples: [LauncherSuggestionExample], now: Date) -> [String: Double] {
        var totals: [String: (sum: Double, count: Int)] = [:]
        for example in examples {
            let prior = totals[example.targetID] ?? (0, 0)
            totals[example.targetID] = (prior.sum + exp(-now.timeIntervalSince(example.date) / (21 * 86_400)), prior.count + 1)
        }
        return totals.mapValues { $0.sum / Double($0.count) }
    }

    /// All encoding, scoring, and evidence work occurs off MainActor, over value snapshots.
    @concurrent static func prediction(engine: LauncherSuggestionEngine, context: LauncherSuggestionContext,
                                      document: LauncherSuggestionDocument, excluded: Set<String>, now: Date,
                                      tuning: LauncherSuggestionTuning, coreML: LauncherSuggestionCoreML) async throws -> LauncherSuggestionEvaluation {
        try Task.checkCancellation()
        let start = ContinuousClock.now
        let examples = retainedExamples(document: document, excluded: excluded, now: now)
        let raw: [String: Double]
        var modelResult: LauncherSuggestionCoreMLResult?
        switch engine {
        case .baseline:
            raw = LauncherSuggestionBaseline.rawScores(context: context, examples: examples, excluded: excluded, now: now)
        case .coreML:
            let prediction = try await coreML.prediction(context: context, examples: examples, now: now, numberOfNeighbors: tuning.clamped.neighbors)
            modelResult = prediction
            raw = prediction.scores
        }
        try Task.checkCancellation()
        var result = evaluate(engine: engine, raw: raw, context: context, document: document, excluded: excluded, now: now, tuning: tuning)
        result.preparationMilliseconds = modelResult?.preparationMilliseconds
        result.inferenceMilliseconds = modelResult?.inferenceMilliseconds
        result.cacheReused = modelResult?.cacheReused
        result.effectiveNeighbors = modelResult?.effectiveNeighbors
        let elapsed = start.duration(to: .now).components
        result.elapsedMilliseconds = Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
        try Task.checkCancellation()
        return result
    }
}
