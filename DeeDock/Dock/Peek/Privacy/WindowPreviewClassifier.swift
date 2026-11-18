import CoreGraphics
import Foundation
import Vision

nonisolated enum WindowPreviewDecision: Sendable {
    case clear, sensitive, unavailable
}

nonisolated protocol WindowPreviewClassifying: Sendable {
    func classify(_ image: CGImage) async -> WindowPreviewDecision
}

/// Wraps the exact image passed to the classifier. Callers cannot substitute a second image.
nonisolated struct ClassifiedWindowPreview: Sendable {
    let id = UUID()
    let decision: WindowPreviewDecision
    private let image: CGImage?

    var clearedImage: CGImage? { decision == .clear ? image : nil }

    fileprivate init(image: CGImage, decision: WindowPreviewDecision) {
        self.image = decision == .unavailable ? nil : image
        self.decision = decision
    }

    static func classify(_ image: CGImage, using classifier: any WindowPreviewClassifying) async -> Self {
        let decision = await classifier.classify(image)
        return Self(image: image, decision: decision)
    }

    fileprivate var revealableImage: CGImage? { decision == .sensitive ? image : nil }
}

/// A grant belongs to one presentation, one selected window, and one frame. Replacing the
/// presentation state, switching windows, or recapturing the window cannot carry the grant over.
nonisolated struct WindowPreviewReveal<WindowID: Equatable> {
    private var window: WindowID?
    private var frame: UUID?

    mutating func select(_ window: WindowID?) {
        guard self.window != window else { return }
        self.window = window
        frame = nil
    }

    mutating func reveal(_ preview: ClassifiedWindowPreview, for window: WindowID) {
        guard preview.decision == .sensitive else { return }
        select(window)
        frame = preview.id
    }

    mutating func hide(_ preview: ClassifiedWindowPreview, for window: WindowID) {
        guard self.window == window, frame == preview.id else { return }
        frame = nil
    }

    func image(_ preview: ClassifiedWindowPreview, for window: WindowID) -> CGImage? {
        if let cleared = preview.clearedImage { return cleared }
        guard self.window == window, frame == preview.id else { return nil }
        return preview.revealableImage
    }
}

/// Shared by the capture actors. Model loading and synchronous Vision work run on this actor.
/// The actor caches only the model. A screenshot and its OCR observations live for one request.
actor CoreMLWindowPreviewClassifier: WindowPreviewClassifying {
    static let shared = CoreMLWindowPreviewClassifier()
    private let modelURL: URL?
    private var model: VNCoreMLModel?
    private var attemptedLoad = false

    init(modelURL: URL? = Bundle.main.url(forResource: "SensitiveWindowPreview", withExtension: "mlmodelc")) {
        self.modelURL = modelURL
    }

    func classify(_ image: CGImage) -> WindowPreviewDecision {
        guard !Task.isCancelled else { return .unavailable }
        if !attemptedLoad {
            attemptedLoad = true
            if let modelURL { model = try? WindowPreviewScoring.load(modelURL) }
        }
        guard let model else { return .unavailable }
        do {
            let score = try WindowPreviewScoring.score(image, model: model)
            if score >= WindowPreviewScoring.threshold { return .sensitive }
            return try WindowPreviewScoring.textSignal(image) ? .sensitive : .clear
        } catch {
            return .unavailable
        }
    }
}
