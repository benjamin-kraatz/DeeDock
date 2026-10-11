import Foundation

/// `LookoutBench probe-full`: the indexer's configuration (text model plus the image and audio encoders) in a fresh
/// process: its load, single image embeds at two budgets, and a batch of documents.
enum FullProbe {
    static let imageRuns = 5
    static let batchRuns = 3

    static func run(models: URL, references: URL?) throws {
        BenchResults.report(memoryAt: "full.before")
        let models = try LlamaModels.locate(in: models)
        let (embedder, load) = try Stopwatch.time { try LlamaEmbedder(models: models, textOnly: false) }
        defer { embedder.close() }
        BenchResults.report("full.loadSeconds", load)
        BenchResults.report(memoryAt: "full.loaded")

        if let references {
            for (file, key) in [("photo.jpg", "photo"), ("screen.png", "screen")] {
                let path = references.appendingPathComponent(file).path
                for budget in [280, 140] {
                    // The first embed at a size builds that size's pipelines; the gate is about the steady state.
                    let (_, first) = try Stopwatch.time { try embedImage(embedder, path, budget) }
                    var runs: [Double] = []
                    for _ in 0..<imageRuns {
                        runs.append(try Stopwatch.time { try embedImage(embedder, path, budget) }.seconds * 1000)
                    }
                    BenchResults.report("full.image.\(key).\(budget).firstMs", first * 1000)
                    BenchResults.report("full.image.\(key).\(budget).medianMs", Samples(runs).median)
                }
            }
        }

        let documents = BenchInputs.documents.map { Prompts.document(title: $0.title, text: $0.text) }
        BenchResults.report("full.batch.count", Double(documents.count))
        BenchResults.report("full.batch.meanCharacters",
                            Double(BenchInputs.documents.reduce(0) { $0 + $1.text.count }) / Double(documents.count))
        let (_, first) = try Stopwatch.time { try embedBatch(embedder, documents) }
        var runs: [Double] = []
        for _ in 0..<batchRuns { runs.append(try Stopwatch.time { try embedBatch(embedder, documents) }.seconds * 1000) }
        BenchResults.report("full.batch.firstMs", first * 1000)
        BenchResults.report("full.batch.medianMs", Samples(runs).median)
        BenchResults.report(memoryAt: "full.worked")
    }

    private static func embedImage(_ embedder: LlamaEmbedder, _ path: String, _ budget: Int) throws {
        let embedding = try embedder.embedImages([path], budget: budget)[0]
        guard embedding.vector != nil else { throw BenchFailure("\(path): \(embedding.error ?? "no vector")") }
    }

    private static func embedBatch(_ embedder: LlamaEmbedder, _ documents: [String]) throws {
        let vectors = try embedder.embedTexts(documents)
        guard vectors.count == documents.count else {
            throw BenchFailure("\(documents.count) documents made \(vectors.count) vectors")
        }
    }
}
