// Adapted from DigUp (MIT, © 2026 Abdur Rahim) — https://github.com/ARahim3/DigUp

import CoreGraphics
import Vision

/// Apple Vision text recognition, for screenshots (keyword search only) and garbled Arabic PDF pages.
///
/// It runs in the index service, never in the app: Vision keeps ~100 MB of models cached in whatever process ran OCR
/// (DigUp measured its app going from 16 to 93 MB after 11 screenshots, and staying there), and all of it goes back
/// to the system when the service exits.
nonisolated enum ScreenshotOCR {
    /// ~0.1 s for a 1440×900 screenshot on an M4 Pro. Runs on the full-resolution image; small UI text is what
    /// screenshots are full of. Accurate beats fast here: fast saved only 8% of screenshot indexing time once OCR
    /// overlapped with embedding, read 9% fewer characters, and lost an exact lookup
    /// ("externally-managed-environment") (2026-10-07).
    static func text(in image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    /// Accurate recognition reads Arabic on this system (macOS 15 and later).
    static let readsArabic: Bool = {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        return (try? request.supportedRecognitionLanguages())?.contains { $0.hasPrefix("ar") } ?? false
    }()
}
