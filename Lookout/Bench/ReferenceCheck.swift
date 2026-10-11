// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

import Foundation

/// `LookoutBench reference`: the vectors this build makes for DigUp's fixed inputs, against the ones
/// `LlamaEmbedder.vectorVersion` stands for (DigUp's Tests/LlamaRuntimeTests/Reference/vectors.json).
///
/// The inputs go in as DigUp's indexer hands them over, built exactly as its `ReferenceVectorTests` builds them: texts
/// with the prompts, a screenshot as PNG (280 tokens), a photo as JPEG (140, and 70 as a video frame) and a 16 kHz
/// WAV, all read by llama.cpp's own decoders. A llama.cpp update must pass this before it ships: indexes record the
/// vector version, not the llama.cpp build.
enum ReferenceCheck {
    /// Lookout's gate. DigUp's test asks for 0.999, what agreeing runtimes (mlx-vlm and llama.cpp) measure; the
    /// report prints whether that holds too.
    static let gate: Float = 0.99
    static let agreement: Float = 0.999

    static let texts: [(name: String, text: String)] = [
        ("query", Prompts.query("payment declined error")),
        ("query-bn", Prompts.query("ইলিশ মাছ রান্না")),
        ("query-ar", Prompts.query("متى تغلق المكتبة")),
        ("document", Prompts.document(title: "Tokyo itinerary", text: "Flight to Tokyo Haneda on November 3. Then the "
                                      + "train to Kamakura to see the Great Buddha, and back for dinner in Shibuya.")),
        // About 1,800 tokens: past the sliding attention window, so the global layers count as well.
        ("document-long", Prompts.document(title: nil, text: (1...60).map {
            "Note \($0): the review moved to room \($0 % 7 + 2) because the projector in the main hall failed again, "
                + "and the team agreed to send the slides the night before."
        }.joined(separator: " "))),
    ]
    static let images = [("screen-280", "screen.png", 280), ("photo-140", "photo.jpg", 140), ("frame-70", "photo.jpg", 70)]

    /// vectors.json.
    struct Reference: Codable {
        let vectorVersion: Int
        let madeWith: String
        let vectors: [String: [Float]]

        enum CodingKeys: String, CodingKey {
            case vectorVersion = "vector_version", madeWith = "made_with", vectors
        }
    }

    /// Prints each cosine and returns the exit status: 0 when every stored vector is matched at `gate` or better.
    /// `reportResults` adds the `BenchResults` lines `bench` reads when it runs this as a child.
    ///
    /// - Throws: The model or the reference files can't be read.
    static func run(models: URL, references: URL, reportResults: Bool = false) throws -> Int32 {
        let stored = try JSONDecoder().decode(Reference.self,
                                              from: Data(contentsOf: references.appendingPathComponent("vectors.json")))
        let embedder = try LlamaEmbedder(models: LlamaModels.locate(in: models), textOnly: false)
        defer { embedder.close() }
        print("llama.cpp \(LlamaEmbedder.buildTag), vectors \(LlamaEmbedder.vectorVersion); reference: vectors "
              + "\(stored.vectorVersion) made with \(stored.madeWith)")
        var made: [String: [Float]] = [:]
        for (input, vector) in zip(texts, try embedder.embedTexts(texts.map(\.text))) { made[input.name] = vector }
        for (name, file, budget) in images {
            let embedding = try embedder.embedImages([references.appendingPathComponent(file).path], budget: budget)[0]
            guard let vector = embedding.vector else { throw BenchFailure("\(file): \(embedding.error ?? "no vector")") }
            made[name] = vector
        }
        let speech = try embedder.embedAudio([references.appendingPathComponent("speech.wav").path])[0]
        guard let vector = speech.vector else { throw BenchFailure("speech.wav: \(speech.error ?? "no vector")") }
        made["speech"] = vector

        var passed = stored.vectorVersion == LlamaEmbedder.vectorVersion
        if !passed { print("FAIL the reference is for vectors \(stored.vectorVersion)") }
        for name in Set(made.keys).symmetricDifference(stored.vectors.keys).sorted() {
            print("FAIL \(name): only on one side")
            passed = false
        }
        var lowest: Float = 1
        for (name, vector) in made.sorted(by: { $0.key < $1.key }) {
            guard let expected = stored.vectors[name] else { continue }
            // Both sides are L2-normalized, so the dot product is the cosine.
            let cosine = zip(vector, expected).reduce(0) { $0 + $1.0 * $1.1 }
            lowest = min(lowest, cosine)
            let verdict = cosine >= gate ? "ok  " : "FAIL"
            print("\(verdict) \(name.padding(toLength: 14, withPad: " ", startingAt: 0)) cosine \(String(format: "%.6f", cosine))")
            if cosine < gate { passed = false }
        }
        if reportResults {
            BenchResults.report("reference.lowestCosine", Double(lowest))
            BenchResults.report("reference.passed", passed ? 1 : 0)
        }
        print("lowest cosine \(String(format: "%.6f", lowest)): \(lowest >= gate ? "passes" : "fails") ≥ \(gate); "
              + "\(lowest >= agreement ? "also meets" : "misses") DigUp's \(agreement)")
        return passed ? 0 : 1
    }
}
