import SwiftUI
import VisionKit

/// VisionKit's Live Text and Visual Look Up over the picture.
///
/// The overlay sits exactly on the picture, so `contentsRect` is the whole view and no tracking
/// image view is needed. Analysis runs once per picture and is cancelled when the picture changes
/// or the view goes away. Selection is read back through the session for Copy Text and Search Web.
struct WindowMarkupLiveTextView: NSViewRepresentable {
    let image: CGImage
    let session: WindowMarkupSession

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ImageAnalysisOverlayView {
        let overlay = ImageAnalysisOverlayView()
        overlay.delegate = context.coordinator
        overlay.preferredInteractionTypes = [.automatic]
        overlay.isSupplementaryInterfaceHidden = false
        context.coordinator.overlay = overlay
        context.coordinator.session = session
        session.liveTextSelection = { [weak overlay] in
            guard let overlay, overlay.hasActiveTextSelection else { return nil }
            return overlay.selectedText
        }
        context.coordinator.analyze(image, in: overlay)
        return overlay
    }

    func updateNSView(_ overlay: ImageAnalysisOverlayView, context: Context) {
        guard context.coordinator.analyzed !== image else { return }
        context.coordinator.analyze(image, in: overlay)
    }

    static func dismantleNSView(_ overlay: ImageAnalysisOverlayView, coordinator: Coordinator) {
        coordinator.task?.cancel()
        coordinator.task = nil
        coordinator.session?.liveTextSelection = nil
        overlay.analysis = nil
    }

    @MainActor
    final class Coordinator: NSObject, ImageAnalysisOverlayViewDelegate {
        weak var overlay: ImageAnalysisOverlayView?
        weak var session: WindowMarkupSession?
        var task: Task<Void, Never>?
        var analyzed: CGImage?

        func analyze(_ image: CGImage, in overlay: ImageAnalysisOverlayView) {
            task?.cancel()
            analyzed = image
            overlay.analysis = nil
            guard ImageAnalyzer.isSupported else { return }
            let analyzer = ImageAnalyzer()
            task = Task { @MainActor [weak overlay] in
                let configuration = ImageAnalyzer.Configuration([.text, .visualLookUp])
                let analysis = try? await analyzer.analyze(image, orientation: .up, configuration: configuration)
                guard !Task.isCancelled, let overlay else { return }
                overlay.analysis = analysis
            }
        }

        nonisolated func contentsRect(for overlayView: ImageAnalysisOverlayView) -> CGRect {
            CGRect(x: 0, y: 0, width: 1, height: 1)
        }
    }
}
