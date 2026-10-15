// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

/// The four calls an embedding runtime answers. Lookout has one runtime, `LlamaEmbedder` (llama.cpp linked into the
/// service process); the protocol is the seam DigUp's tests and evals use to swap it.
///
/// One thread at a time: implementations aren't thread-safe, and their owner serializes the calls.
nonisolated protocol Embedder: AnyObject {
    var info: WorkerInfo { get }
    /// One L2-normalized vector per text, in order.
    func embedTexts(_ texts: [String]) throws -> [[Float]]
    /// One embedding per image file, in order. `budget` is the number of soft tokens the image is resized to fill.
    func embedImages(_ paths: [String], budget: Int) throws -> [Embedding]
    /// One embedding per audio file, in order (the first 30 s of each).
    func embedAudio(_ paths: [String]) throws -> [Embedding]
    /// Frees the model. Safe to call twice.
    func close()
}

/// One embedding (or why the file couldn't be embedded).
nonisolated struct Embedding: Sendable {
    let vector: [Float]?
    let error: String?
}
