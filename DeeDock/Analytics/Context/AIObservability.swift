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

    /// Credential shapes scrubbed from every payload: Anthropic and OpenAI keys (`sk-…`), GitHub
    /// tokens, AWS access key IDs, Google API keys and Slack tokens. Window text, copied text or an
    /// error can contain one, so every payload is scrubbed before it is captured, whichever
    /// feature or model produced it. Anthropic's pattern comes first, so its keys are replaced
    /// whole before the broader `sk-` pattern runs.
    private static let credentialPatterns = [
        #"\bsk-ant-[A-Za-z0-9_\-]{16,}"#,
        #"\bsk-[A-Za-z0-9_\-]{20,}"#,
        #"gh[pousr]_[A-Za-z0-9]{36,}"#,
        #"github_pat_[A-Za-z0-9_]{22,}"#,
        #"\bAKIA[0-9A-Z]{16}\b"#,
        #"AIza[0-9A-Za-z_\-]{35}"#,
        #"xox[abposr]-[A-Za-z0-9\-]{10,}"#,
    ]

    /// Replaces anything that looks like an API key or access token with a placeholder.
    static func redacted(_ text: String) -> String {
        credentialPatterns.reduce(text) { result, pattern in
            result.replacingOccurrences(of: pattern, with: "[API key]", options: .regularExpression)
        }
    }

    /// Token counts a model reported for one generation.
    nonisolated struct Usage: Sendable {
        /// Prompt tokens. With cache counts set, the uncached remainder only: PostHog treats
        /// Anthropic's cache tokens as separate from `$ai_input_tokens` when it works out cost, so
        /// a total here would charge them twice.
        let input: Int
        let output: Int
        var cacheRead: Int? = nil
        var cacheCreation: Int? = nil
    }

    /// What the Claude API said about prompt caching for one generation.
    nonisolated struct CacheDiagnostics: Sendable {
        /// One entry per API request, in order: `first_request`, `no_divergence`, `pending`, or the
        /// API's `cache_miss_reason` type.
        let outcomes: [String]
        /// The API's estimate of the prompt lost to those misses, a magnitude and not a bill.
        let missedInputTokens: Int
    }

    /// Why a generation failed, as a closed set of values. A generation that withholds its content
    /// (`includesContent: false`) reports only this: an error's own text can carry a server
    /// message, a host name, or words from the prompt. Map an `Error` with
    /// `AIObservability.ErrorCode(_:)` (in `AIObservabilityErrorCode.swift`).
    nonisolated enum ErrorCode: String, Sendable, CaseIterable {
        case contextExceeded = "context_exceeded"
        case rateLimited = "rate_limited"
        case guardrail
        case refusal
        case unsupportedLanguage = "unsupported_language"
        case unsupported
        case timeout
        case offline
        case network
        case credential
        case unavailable
        case other
    }

    /// Sends one `$ai_generation`. Defaults describe Apple's on-device model; a caller using
    /// another model passes its own `model` and `provider`. Credentials are never part of a
    /// generation: callers pass only the prompt, the instructions and the answer, and anything in
    /// them that looks like an API key or access token is replaced (`redacted(_:)`) before sending.
    ///
    /// - Parameters:
    ///   - instructions: The session's instructions, sent as a system message before `input`.
    ///   - usage: Token counts, when the model reports them.
    ///   - cacheDiagnostics: The cache comparison, for a request that opted in to one.
    ///   - error: A message safe to show the person, for a generation that failed. Sent only when
    ///     `includesContent` is true.
    ///   - errorCode: Why the generation failed, from a closed set. With `includesContent` false
    ///     this is the only error value sent; a free-form `error` is replaced by it, or by `other`.
    ///   - includesContent: False leaves the instructions, the prompt, the answer, and any
    ///     free-form error text out of this one generation, whatever `capturesContent` says: only
    ///     metadata (model, latency, token counts, the error code) is sent. Flix Files passes false
    ///     for every call, because its prompts carry file names and file contents.
    static func capture(trace: Trace, name: String, input: String, output: String? = nil,
                        startedAt: Date, maximumResponseTokens: Int? = nil, stream: Bool = false,
                        model: String = "apple_foundation_models", provider: String = "apple",
                        instructions: String? = nil, usage: Usage? = nil,
                        cacheDiagnostics: CacheDiagnostics? = nil, error: String? = nil,
                        errorCode: ErrorCode? = nil, includesContent: Bool = true) async {
        let properties = properties(trace: trace, name: name, input: input, output: output, startedAt: startedAt,
                                    maximumResponseTokens: maximumResponseTokens, stream: stream, model: model,
                                    provider: provider, instructions: instructions, usage: usage,
                                    cacheDiagnostics: cacheDiagnostics, error: error, errorCode: errorCode,
                                    includesContent: includesContent)
        await Analytics.captureAI(AIObservabilityRecord(name: "$ai_generation", properties: properties))
    }

    /// The `$ai_generation` properties ``capture(trace:name:input:output:startedAt:maximumResponseTokens:stream:model:provider:instructions:usage:cacheDiagnostics:error:errorCode:includesContent:)``
    /// sends, built apart from sending so the content opt-out can be checked without a backend.
    static func properties(trace: Trace, name: String, input: String, output: String? = nil,
                           startedAt: Date, maximumResponseTokens: Int? = nil, stream: Bool = false,
                           model: String = "apple_foundation_models", provider: String = "apple",
                           instructions: String? = nil, usage: Usage? = nil,
                           cacheDiagnostics: CacheDiagnostics? = nil, error: String? = nil,
                           errorCode: ErrorCode? = nil, includesContent: Bool = true) -> [String: Any] {
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
            if let cacheRead = usage.cacheRead { properties["$ai_cache_read_input_tokens"] = cacheRead }
            if let cacheCreation = usage.cacheCreation { properties["$ai_cache_creation_input_tokens"] = cacheCreation }
        }
        if let cacheDiagnostics, !cacheDiagnostics.outcomes.isEmpty {
            properties["cache_diagnostics"] = cacheDiagnostics.outcomes
            properties["cache_missed_input_tokens"] = cacheDiagnostics.missedInputTokens
        }
        if error != nil || errorCode != nil {
            properties["$ai_is_error"] = true
            // Withheld content withholds error text too: only the closed code leaves the Mac.
            if includesContent, let error {
                properties["$ai_error"] = redacted(error)
            } else {
                properties["$ai_error"] = (errorCode ?? .other).rawValue
            }
        }
        if capturesContent, includesContent {
            var messages: [[String: String]] = []
            if let instructions { messages.append(["role": "system", "content": redacted(instructions)]) }
            messages.append(["role": "user", "content": redacted(input)])
            properties["$ai_input"] = messages
            if let output { properties["$ai_output_choices"] = [["role": "assistant", "content": redacted(output)]] }
        }
        return properties
    }
}

/// Bypasses the product-analytics property allowlist only for documented `$ai_*` manual-capture
/// fields and the cache diagnostics listed in docs/ANALYTICS.md.
nonisolated struct AIObservabilityRecord: @unchecked Sendable {
    let name: String
    let properties: [String: Any]
}
