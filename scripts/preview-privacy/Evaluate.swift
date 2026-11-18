import CoreGraphics
import CoreML
import Foundation
import ImageIO
import Vision

@main
struct Evaluate {
    struct Sample {
        let category: String
        let score: Float
        let textSignal: Bool
        let modelMS: Double
        let textMS: Double
        var sensitive: Bool { ["signin", "code", "private-chat"].contains(category) }
    }

    static func main() throws {
        guard [3, 4].contains(CommandLine.arguments.count) else {
            print("Usage: evaluate DATASET MODEL.mlmodel [validation|test]")
            exit(2)
        }
        let data = URL(filePath: CommandLine.arguments[1])
        let compiled = try MLModel.compileModel(at: URL(filePath: CommandLine.arguments[2]))
        defer { try? FileManager.default.removeItem(at: compiled) }
        let model = try WindowPreviewScoring.load(compiled)
        let splits = CommandLine.arguments.count == 4 ? [CommandLine.arguments[3]] : ["validation", "test"]
        for split in splits {
            let samples = try read(split: data.appending(path: split), model: model)
            print("\n\(split) \(samples.count) synthetic thumbnails")
            let selected = [Float(0.02), 0.05, 0.10, 0.15, 0.20, 0.30, 0.40, 0.50, 0.60, 0.70, 1.01]
                .min { cost(samples, $0) < cost(samples, $1) }!
            if split == "validation" {
                for threshold: Float in [0.02, 0.05, 0.10, 0.15, 0.20, 0.30, 0.40, 0.50, 0.60, 0.70, 1.01] {
                    print("threshold \(threshold) validation cost \(cost(samples, threshold))")
                }
                print("Lowest validation cost at \(selected) (5 × missed sensitive + ordinary blocked)")
            }
            let threshold = WindowPreviewScoring.threshold
            for useOCR in [false, true] {
                print("Threshold \(threshold), OCR \(useOCR)")
                for category in Set(samples.map(\.category)).sorted() {
                    let subset = samples.filter { $0.category == category }
                    let errors = subset.count { $0.sensitive != blocked($0, threshold, useOCR) }
                    print("  \(category): \(errors)/\(subset.count) \(subset[0].sensitive ? "missed" : "blocked")")
                }
                let durations = samples.map { $0.modelMS + (useOCR && $0.score < threshold ? $0.textMS : 0) }.sorted()
                print(String(format: "  latency p50 %.2f ms, p95 %.2f ms", durations[durations.count / 2],
                             durations[Int(Double(durations.count) * 0.95)]))
            }
        }
    }

    static func blocked(_ sample: Sample, _ threshold: Float, _ useOCR: Bool) -> Bool {
        sample.score >= threshold || (useOCR && sample.textSignal)
    }

    static func cost(_ samples: [Sample], _ threshold: Float) -> Int {
        samples.reduce(0) { cost, sample in
            cost + (sample.sensitive == blocked(sample, threshold, true) ? 0 : sample.sensitive ? 5 : 1)
        }
    }

    static func read(split: URL, model: VNCoreMLModel) throws -> [Sample] {
        let paths = try ["ordinary", "sensitive"].flatMap {
            try FileManager.default.contentsOfDirectory(at: split.appending(path: $0), includingPropertiesForKeys: nil)
        }.filter { $0.pathExtension == "png" }.sorted { $0.path < $1.path }
        return try paths.map { path in
            guard let source = CGImageSourceCreateWithURL(path as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let category = path.lastPathComponent.split(separator: "_").first else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let startModel = DispatchTime.now().uptimeNanoseconds
            let score = try WindowPreviewScoring.score(image, model: model)
            let startText = DispatchTime.now().uptimeNanoseconds
            let text = try WindowPreviewScoring.textSignal(image)
            let end = DispatchTime.now().uptimeNanoseconds
            return Sample(category: String(category), score: score, textSignal: text,
                          modelMS: Double(startText - startModel) / 1_000_000,
                          textMS: Double(end - startText) / 1_000_000)
        }
    }
}
