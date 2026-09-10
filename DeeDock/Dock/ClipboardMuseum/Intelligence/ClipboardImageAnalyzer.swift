import Foundation
import Vision

/// What Vision found in a copied image.
nonisolated struct ClipboardImageAnalysis: Equatable, Sendable {
    var labels: [String]
    var text: String
}

/// On-device image classification and text recognition. Runs off the main actor after an image
/// exhibit is stored, so capture never waits for it.
nonisolated enum ClipboardImageAnalyzer {
    /// Labels under this confidence are noise for search and the placard.
    static let minimumConfidence: Float = 0.3

    /// - Returns: Up to six labels (English taxonomy identifiers, underscores as spaces) and the
    ///   recognized lines joined by newlines. Either part is empty when Vision fails or finds nothing.
    static func analyze(png: Data) async -> ClipboardImageAnalysis {
        var labels: [String] = []
        if let observations = try? await ClassifyImageRequest().perform(on: png, orientation: nil) {
            labels = observations
                .filter { $0.confidence >= minimumConfidence }
                .sorted { $0.confidence > $1.confidence }
                .prefix(6)
                .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
        }
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        var text = ""
        if let observations = try? await request.perform(on: png, orientation: nil) {
            text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }
        return ClipboardImageAnalysis(labels: labels,
                                      text: String(text.prefix(ClipboardMuseumLimits.maximumTextCharacters)))
    }
}
