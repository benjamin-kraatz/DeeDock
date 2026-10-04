import Foundation

/// Manual AI Observability capture for Apple Foundation Models, which has no supported SDK wrapper.
///
/// Calls stay anonymous because DeeDock has no authenticated account identity. One process owns one
/// AI session; callers create one trace for each user-triggered generation workflow and reuse it for
/// every model call within that workflow.
nonisolated enum AIObservability {
    nonisolated struct Trace: Sendable {
        fileprivate let id = UUID().uuidString
    }

    private static let sessionID = UUID().uuidString
    /// Manual capture intentionally includes prompt and completion content, matching privacy mode off.
    /// Set to false before sending sensitive model inputs or outputs to omit those payload fields.
    private static let capturesContent = true

    static func makeTrace() -> Trace { Trace() }

    static func capture(trace: Trace, name: String, input: String, output: String? = nil,
                        startedAt: Date, maximumResponseTokens: Int? = nil, stream: Bool = false) async {
        var properties: [String: Any] = [
            "$ai_trace_id": trace.id,
            "$ai_session_id": sessionID,
            "$ai_span_id": UUID().uuidString,
            "$ai_span_name": name,
            "$ai_model": "apple_foundation_models",
            "$ai_provider": "apple",
            "$ai_latency": max(0, Date().timeIntervalSince(startedAt)),
            "$ai_stream": stream,
        ]
        if let maximumResponseTokens { properties["$ai_max_tokens"] = maximumResponseTokens }
        if capturesContent {
            properties["$ai_input"] = [["role": "user", "content": input]]
            if let output { properties["$ai_output_choices"] = [["role": "assistant", "content": output]] }
        }
        await Analytics.captureAI(AIObservabilityRecord(name: "$ai_generation", properties: properties))
    }
}

/// Bypasses the product-analytics property allowlist only for documented `$ai_*` manual-capture fields.
nonisolated struct AIObservabilityRecord: @unchecked Sendable {
    let name: String
    let properties: [String: Any]
}
