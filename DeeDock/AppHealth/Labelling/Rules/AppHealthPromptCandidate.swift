import Foundation

/// An app the suspicion rule or the ordinary heavy-use check picked out in one tick, before the prompt policy
/// decides whether to ask about it.
nonisolated struct AppHealthPromptCandidate: Equatable, Sendable {
    let app: String
    let kind: AppHealthAppKind
    /// `rule` or `ordinary`; manual labels never pass through the policy.
    let trigger: AppHealthPromptTrigger
    /// Every flag that held, for `rule`. Empty for `ordinary`.
    let reasons: [AppHealthPromptReason]
    let evidence: AppHealthSuspicionEvidence

    /// Runs the suspicion rule over one app's history.
    ///
    /// - Returns: A `rule` candidate when the app is suspicious, an `ordinary` one when it is busy but not
    ///   suspicious, nil otherwise.
    static func evaluate(app: String, kind: AppHealthAppKind, history: [AppHealthSample],
                         idleSeconds: Int) -> AppHealthPromptCandidate? {
        let suspicion = AppHealthSuspicionRule.evaluate(history, idleSeconds: idleSeconds)
        switch suspicion.verdict {
        case .suspicious:
            return AppHealthPromptCandidate(app: app, kind: kind, trigger: .rule, reasons: suspicion.reasons,
                                            evidence: suspicion.evidence)
        case .ordinary:
            return AppHealthPromptCandidate(app: app, kind: kind, trigger: .ordinary, reasons: [],
                                            evidence: suspicion.evidence)
        case .none:
            return nil
        }
    }
}
