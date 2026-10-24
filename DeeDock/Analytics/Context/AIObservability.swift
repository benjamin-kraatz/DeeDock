import Foundation

/// Manual AI Observability capture for Foundation Models sessions, which have no supported SDK
/// wrapper: Apple's on-device model, and Claude through the same `LanguageModelSession` API in Robi.
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

    /// Anthropic API keys (`sk-ant-…`). Window text, copied text or an error can contain one, so
    /// every payload is scrubbed before it is captured, whichever feature or model produced it.
    private static let anthropicKey = #"sk-ant-[A-Za-z0-9_\-]{16,}"#

    /// Replaces anything that looks like an Anthropic API key with a placeholder.
    static func redacted(_ text: String) -> String {
        guard text.contains("sk-ant-") else { return text }
        return text.replacingOccurrences(of: anthropicKey, with: "[API key]", options: .regularExpression)
    }

    /// Token counts a model reported for one generation.
    nonisolated struct Usage: Sendable {
        let input: Int
        let output: Int
    }

    /// Sends one `$ai_generation`. Defaults describe Apple's on-device model; a caller using
    /// another model passes its own `model` and `provider`. Credentials are never part of a
    /// generation: callers pass only the prompt, the instructions and the answer, and anything in
    /// them that looks like an Anthropic API key is replaced (`redacted(_:)`) before sending.
    ///
    /// - Parameters:
    ///   - instructions: The session's instructions, sent as a system message before `input`.
    ///   - usage: Token counts, when the model reports them.
    ///   - error: A message safe to show the person, for a generation that failed.
    static func capture(trace: Trace, name: String, input: String, output: String? = nil,
                        startedAt: Date, maximumResponseTokens: Int? = nil, stream: Bool = false,
                        model: String = "apple_foundation_models", provider: String = "apple",
                        instructions: String? = nil, usage: Usage? = nil, error: String? = nil) async {
        var properties: [String: Any] = [
            "$ai_trace_id": trace.id,
            "$ai_session_id": sessionID,
            "$ai_span_id": UUID().uuidString,
            "$ai_span_name": name,
            "$ai_model": model,
            "$ai_provider": provider,
            "$ai_latency": max(0, Date().timeIntervalSince(startedAt)),
            "$ai_stream": stream,
        ]
        if let maximumResponseTokens { properties["$ai_max_tokens"] = maximumResponseTokens }
        if let usage {
            properties["$ai_input_tokens"] = usage.input
            properties["$ai_output_tokens"] = usage.output
        }
        if let error {
            properties["$ai_is_error"] = true
            properties["$ai_error"] = redacted(error)
        }
        if capturesContent {
            var messages: [[String: String]] = []
            if let instructions { messages.append(["role": "system", "content": redacted(instructions)]) }
            messages.append(["role": "user", "content": redacted(input)])
            properties["$ai_input"] = messages
            if let output { properties["$ai_output_choices"] = [["role": "assistant", "content": redacted(output)]] }
        }
        await Analytics.captureAI(AIObservabilityRecord(name: "$ai_generation", properties: properties))
    }
}

/// Bypasses the product-analytics property allowlist only for documented `$ai_*` manual-capture fields.
nonisolated struct AIObservabilityRecord: @unchecked Sendable {
    let name: String
    let properties: [String: Any]
}
