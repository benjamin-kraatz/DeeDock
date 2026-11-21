import CoreGraphics
import Foundation
import FoundationModels

/// Every Apple Intelligence call Flix Files makes goes through here: one fresh session per call,
/// greedy sampling, a hard timeout, silent failure, and observability without content.
///
/// The prompts carry file names and file contents, so each call reports metadata only to AI
/// observability (`AIObservability.capture(…, includesContent: false)`): the span name, latency,
/// token limit, and a closed error code (`AIObservability.ErrorCode`), never an error's text. Callers treat a nil result as "no answer" and use their rule
/// fallback; nothing is retried. Each such fallback counts toward `flix_ai_failures`.
///
/// Main actor: sessions are created and awaited here; the model itself runs out of process.
@MainActor
enum FlixLanguageModel {
    /// Apple Intelligence is on, ready, and can produce structured output.
    static var isAvailable: Bool {
        let model = SystemLanguageModel.default
        return model.availability == .available && model.capabilities.contains(.guidedGeneration)
    }

    /// The on-device model accepts pictures (`Attachment(image)`), on this Mac and OS.
    static var readsImages: Bool {
        isAvailable && SystemLanguageModel.default.capabilities.contains(.vision)
    }

    /// The person's first preferred language, named in English for the model.
    static var language: String { RobiAgent.preferredLanguage }

    /// Generates one `Output` or returns nil when the model is unavailable, refuses, fails, takes
    /// longer than `timeout`, or the calling task is cancelled. Cancelling ends generation.
    ///
    /// - Parameters:
    ///   - span: The `$ai_span_name` observability reports, such as `flix_caption`.
    ///   - image: A picture for the model to look at; dropped when the model reads none.
    static func generate<Output: Generable & Sendable>(_ type: Output.Type, span: String, instructions: String,
                                                       prompt: String, image: CGImage? = nil,
                                                       maximumTokens: Int, timeout: Duration) async -> Output? {
        guard isAvailable, !Task.isCancelled else { return nil }
        let picture = readsImages ? image : nil
        let work = Task { () -> Output in
            let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
            let started = Date()
            do {
                let response = try await session.respond(generating: Output.self,
                                                         options: GenerationOptions(samplingMode: .greedy,
                                                                                    maximumResponseTokens: maximumTokens)) {
                    prompt
                    if let picture { Attachment(picture).label("The file") }
                }
                await observe(span: span, started: started, limit: maximumTokens, error: nil)
                return response.content
            } catch {
                await observe(span: span, started: started, limit: maximumTokens, error: error)
                throw error
            }
        }
        let deadline = Task {
            try? await Task.sleep(for: timeout)
            work.cancel()
        }
        defer { deadline.cancel() }
        let output = await withTaskCancellationHandler {
            try? await work.value
        } onCancel: {
            work.cancel()
        }
        if Task.isCancelled { return nil }
        // A refusal, an error, or the time limit: the caller falls back to its rules.
        if output == nil { Analytics.count(.aiFailures) }
        return output
    }

    private static func observe(span: String, started: Date, limit: Int, error: Error?) async {
        let failure = error.flatMap { $0 is CancellationError ? nil : AIObservability.ErrorCode($0) }
        await AIObservability.capture(trace: AIObservability.makeTrace(), name: span, input: "", startedAt: started,
                                      maximumResponseTokens: limit, errorCode: failure, includesContent: false)
    }
}
