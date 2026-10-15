import Foundation
import ImageIO

/// `LookoutBench probe-image`: searching with a picture the way the query service does it, in a fresh process.
///
/// It starts as the service starts, with the text model only, then loads the image encoder into it on the first
/// picture (`LlamaEmbedder.attachMedia`), as the service does for the first search with a picture. The picture is
/// prepared as the app prepares it (`QueryPicture`), so no file reaches the encoder.
enum ImageProbe {
    static let warmRuns = 10
    /// A photo every Mac has, when `--image` isn't given.
    static let defaultImage = URL(fileURLWithPath: "/System/Library/Desktop Pictures/Sonoma.heic")

    static func run(models: URL, image: URL?) throws {
        BenchResults.report(memoryAt: "image.before")
        let models = try LlamaModels.locate(in: models)
        guard let media = models.media else { throw BenchFailure("no \(ModelFiles.media.name) in the models folder") }
        let (embedder, textStart) = try Stopwatch.time { try LlamaEmbedder(models: models, textOnly: true) }
        defer { embedder.close() }
        BenchResults.report("image.textStartSeconds", textStart)
        BenchResults.report(memoryAt: "image.textLoaded")

        let file = image ?? defaultImage
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else {
            throw BenchFailure("can't read \(file.path)")
        }
        let (screenshot, prepare280) = try Stopwatch.time { try QueryPicture.make(from: source, screenshot: true) }
        let (photo, prepare140) = try Stopwatch.time { try QueryPicture.make(from: source, screenshot: false) }
        BenchResults.report("image.prepare280Ms", prepare280 * 1000)
        BenchResults.report("image.prepare140Ms", prepare140 * 1000)

        // The cold start: the encoder's load (with mtmd's warm-up encode) and the first picture after it.
        let (_, attach) = try Stopwatch.time { try embedder.attachMedia(media) }
        let (_, first) = try Stopwatch.time { try embed(embedder, screenshot) }
        BenchResults.report("image.attachSeconds", attach)
        BenchResults.report("image.firstQueryMs", first * 1000)
        BenchResults.report("image.coldSeconds", attach + first)
        BenchResults.report(memoryAt: "image.attached")

        for (picture, key) in [(screenshot, "280"), (photo, "140")] {
            let (_, firstAtSize) = try Stopwatch.time { try embed(embedder, picture) }
            var runs: [Double] = []
            for _ in 0..<warmRuns { runs.append(try Stopwatch.time { try embed(embedder, picture) }.seconds * 1000) }
            let samples = Samples(runs)
            BenchResults.report("image.warm\(key).firstMs", firstAtSize * 1000)
            BenchResults.report("image.warm\(key).medianMs", samples.median)
            BenchResults.report("image.warm\(key).p95Ms", samples.percentile(95))
        }
        // How far apart one picture lands at the two budgets: whether a query may use the faster one.
        let at280 = try embedder.embedImage(pixels: [UInt8](screenshot.pixels), width: screenshot.width,
                                            height: screenshot.height)
        let at140 = try embedder.embedImage(pixels: [UInt8](photo.pixels), width: photo.width, height: photo.height)
        BenchResults.report("image.budgetCosine", Double(zip(at280, at140).reduce(0) { $0 + $1.0 * $1.1 }))
        // A text query still works beside the encoder, and costs what it did.
        let (_, text) = try Stopwatch.time { try embedder.embedTexts([Prompts.query("the dog on the beach")]) }
        BenchResults.report("image.textAfterMs", text * 1000)
        BenchResults.report(memoryAt: "image.queried")
    }

    private static func embed(_ embedder: LlamaEmbedder, _ picture: QueryPicture) throws {
        let vector = try embedder.embedImage(pixels: [UInt8](picture.pixels), width: picture.width,
                                             height: picture.height)
        guard vector.count == QueryVectorRows.dimension else {
            throw BenchFailure("a picture made \(vector.count) values")
        }
    }
}
