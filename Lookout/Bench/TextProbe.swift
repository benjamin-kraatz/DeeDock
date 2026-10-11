import Foundation

/// `LookoutBench probe-text`: the query encoder's start and its warm queries, in a fresh process.
///
/// The load is timed the way the query service starts: llama.cpp's backend setup, the text model, the context and
/// `LlamaEmbedder`'s two warm-up embeds, which build the Metal pipelines.
enum TextProbe {
    static func run(models: URL) throws {
        BenchResults.report(memoryAt: "text.before")
        let models = try LlamaModels.locate(in: models)
        let (embedder, coldStart) = try Stopwatch.time { try LlamaEmbedder(models: models, textOnly: true) }
        defer { embedder.close() }
        BenchResults.report("text.coldStartSeconds", coldStart)
        BenchResults.report(memoryAt: "text.loaded")

        var latencies: [Double] = []
        for query in BenchInputs.queries {
            let (vectors, seconds) = try Stopwatch.time { try embedder.embedTexts([Prompts.query(query)]) }
            guard vectors.count == 1, vectors[0].count == QueryVectorRows.dimension else {
                throw BenchFailure("query \"\(query)\" made \(vectors.count) vectors")
            }
            latencies.append(seconds * 1000)
        }
        let samples = Samples(latencies)
        BenchResults.report("text.queryCount", Double(latencies.count))
        BenchResults.report("text.queryMedianMs", samples.median)
        BenchResults.report("text.queryP95Ms", samples.percentile(95))
        BenchResults.report("text.queryMinMs", samples.min)
        BenchResults.report("text.queryMaxMs", samples.max)
        BenchResults.report(memoryAt: "text.queried")
    }
}
