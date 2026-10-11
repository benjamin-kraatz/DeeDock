import Foundation

/// The object every XPC connection to `LookoutQueryService` exports: EmbeddingGemma 2's text model on llama.cpp,
/// loaded on the first call and kept until the process ends.
///
/// `LlamaEmbedder` takes one call at a time, and NSXPC delivers messages on its own queues, so every call is moved
/// onto one serial queue that alone touches `embedder`. The queue runs at user-initiated QoS: DigUp measured App Nap
/// and efficiency cores stretching a query from 125 to 650 ms at lower priority. A failed load isn't kept, so a call
/// after the model has been downloaded loads it.
///
/// The process exits 120 s after its last call (`IdleExit`), which returns the model's 215 MB; the next query
/// relaunches it and pays the cold start again (0.3–0.5 s).
final class QueryEncoderService: NSObject, LookoutQueryServing, @unchecked Sendable {
    /// Shared by all connections, so they share one loaded model.
    static let shared = QueryEncoderService()

    /// Seconds without a call before the service exits.
    static let idleSeconds = 120

    private let queue: DispatchQueue
    /// Only read or written on `queue`.
    private var embedder: LlamaEmbedder?
    /// Exiting frees the model with the rest of the process, so there's nothing to clean up first.
    private let idleExit: IdleExit

    override init() {
        let queue = DispatchQueue(label: "Lookout.QueryEncoder", qos: .userInitiated)
        self.queue = queue
        idleExit = IdleExit(after: Self.idleSeconds, on: queue)
        super.init()
    }

    /// Starts the idle countdown for a launch that never gets a call.
    func startIdleCountdown() {
        idleExit.arm()
    }

    func embedQueries(_ texts: [String], reply: @escaping @Sendable (Data?, String?) -> Void) {
        idleExit.disarm()
        queue.async {
            defer { self.idleExit.arm() }
            do {
                let vectors = try self.loadedEmbedder().embedTexts(texts)
                reply(QueryVectorRows.encode(vectors), nil)
            } catch {
                reply(nil, "\(error)")
            }
        }
    }

    func warmUp(reply: @escaping @Sendable (String?) -> Void) {
        idleExit.disarm()
        queue.async {
            defer { self.idleExit.arm() }
            do {
                _ = try self.loadedEmbedder()
                reply(nil)
            } catch {
                reply("\(error)")
            }
        }
    }

    /// The model, loading it (with its warm-up) first if needed. llama.cpp's warnings go to
    /// `Logs/query-service.log`. Call only on `queue`.
    private func loadedEmbedder() throws -> LlamaEmbedder {
        dispatchPrecondition(condition: .onQueue(queue))
        if let embedder { return embedder }
        let models = try LlamaModels.locate(in: QueryModelLocation.folder())
        let log = try? LookoutPaths.standard.logFile("query-service.log")
        let loaded = try LlamaEmbedder(models: models, textOnly: true, log: log)
        embedder = loaded
        return loaded
    }
}
