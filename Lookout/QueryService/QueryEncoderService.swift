import Foundation

/// The object every XPC connection to `LookoutQueryService` exports: EmbeddingGemma 2's text model on llama.cpp,
/// loaded on the first call and kept for the process's lifetime.
///
/// `LlamaEmbedder` takes one call at a time, and NSXPC delivers messages on its own queues, so every call is moved
/// onto one serial queue that alone touches `embedder`. The queue runs at user-initiated QoS: DigUp measured App Nap
/// and efficiency cores stretching a query from 125 to 650 ms at lower priority. A failed load isn't kept, so a call
/// after the model has been downloaded loads it.
final class QueryEncoderService: NSObject, LookoutQueryServing, @unchecked Sendable {
    /// Shared by all connections, so they share one loaded model.
    static let shared = QueryEncoderService()

    private let queue = DispatchQueue(label: "Lookout.QueryEncoder", qos: .userInitiated)
    /// Only read or written on `queue`.
    private var embedder: LlamaEmbedder?

    func embedQueries(_ texts: [String], reply: @escaping @Sendable (Data?, String?) -> Void) {
        queue.async {
            do {
                let vectors = try self.loadedEmbedder().embedTexts(texts)
                reply(QueryVectorRows.encode(vectors), nil)
            } catch {
                reply(nil, "\(error)")
            }
        }
    }

    func warmUp(reply: @escaping @Sendable (String?) -> Void) {
        queue.async {
            do {
                _ = try self.loadedEmbedder()
                reply(nil)
            } catch {
                reply("\(error)")
            }
        }
    }

    /// The model, loading it (with its warm-up) first if needed. Call only on `queue`.
    private func loadedEmbedder() throws -> LlamaEmbedder {
        dispatchPrecondition(condition: .onQueue(queue))
        if let embedder { return embedder }
        let models = try LlamaModels.locate(in: QueryModelLocation.folder())
        let loaded = try LlamaEmbedder(models: models, textOnly: true)
        embedder = loaded
        return loaded
    }
}
