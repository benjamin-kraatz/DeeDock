import CoreGraphics
import Foundation
import Vision

/// Vision reads existing Peek pixels locally. It neither captures windows nor sends requests over a network.
actor PeekHistoryRecognizer {
    func recognize(_ image: CGImage) async throws -> String {
        try Task.checkCancellation()
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = false
        let observations = try await request.perform(on: image)
        try Task.checkCancellation()
        return String(observations.prefix(128).map { String($0.transcript.prefix(512)) }
            .joined(separator: "\n").prefix(8_000)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
