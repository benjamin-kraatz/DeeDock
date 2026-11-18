import CoreGraphics
import CoreML
import Foundation
import Vision

/// Inference shared with the offline evaluator, including image scaling and OCR.
nonisolated enum WindowPreviewScoring {
    static let threshold: Float = 0.40

    enum ScoringError: Error { case missingScore }

    static func load(_ url: URL) throws -> VNCoreMLModel {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine
        return try VNCoreMLModel(for: MLModel(contentsOf: url, configuration: config))
    }

    static func score(_ image: CGImage, model: VNCoreMLModel) throws -> Float {
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFill
        try VNImageRequestHandler(cgImage: image).perform([request])
        guard let score = (request.results as? [VNClassificationObservation])?
            .first(where: { $0.identifier == "sensitive" })?.confidence, score.isFinite else {
            throw ScoringError.missingScore
        }
        return score
    }

    static func textSignal(_ image: CGImage) throws -> Bool {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: textImage(image)).perform([request])
        let lines = (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first?.string.lowercased().trimmingCharacters(in: .punctuationCharacters)
        }
        let headings = ["verification code", "security code", "one-time code", "direct message", "private chat"]
        return lines.contains { line in
            headings.contains(line) || line.hasPrefix("message to ") ||
            line == "password" && lines.contains { $0 == "email address" || $0 == "sign in" }
        }
    }

    // Vision's text detector expects readable glyph sizes. Upsampling does not recover detail
    // discarded by capture, but avoids skipping small glyphs solely because of their pixel height.
    private static func textImage(_ image: CGImage) -> CGImage {
        let longest = max(image.width, image.height)
        let scale = min(3, 1024.0 / Double(longest))
        guard abs(scale - 1) > 0.15,
              let context = CGContext(data: nil, width: Int(Double(image.width) * scale),
                                      height: Int(Double(image.height) * scale), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        return context.makeImage() ?? image
    }
}
