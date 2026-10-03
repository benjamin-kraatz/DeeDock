import AppKit
import Observation
import ScreenCaptureKit
import VideoToolbox

/// Experiment: a live picture of whatever is behind one dock panel, for the Ice Blocks
/// refraction shader.
///
/// Public glass blurs the backdrop, so the only way to bend a sharp one is to capture the
/// screen without DOKK's own windows and redraw that strip inside each block. Capture runs
/// only while the style, the tuning switch, and the dock's visibility all ask for it, needs
/// Screen Recording access, and makes macOS show its capture indicator.
@MainActor @Observable
final class DockIceBackdrop {
    struct Frame {
        let image: CGImage
        /// Backdrop pixels per point.
        let scale: CGFloat
    }

    /// The newest captured strip. It covers the panel's resting window frame, so a view's
    /// window coordinates index straight into it.
    private(set) var frame: Frame?

    @ObservationIgnored private var displayID: CGDirectDisplayID = 0
    /// AppKit global coordinates.
    @ObservationIgnored private var displayFrame = CGRect.zero
    @ObservationIgnored private var rect = CGRect.zero
    @ObservationIgnored private var scale: CGFloat = 2
    @ObservationIgnored private var styleActive = false
    @ObservationIgnored private var visible = false
    @ObservationIgnored private var stopped = false
    @ObservationIgnored private var stream: SCStream?
    @ObservationIgnored private var output: DockIceBackdropOutput?
    @ObservationIgnored private var running: Request?
    /// Invalidates an asynchronous start that a newer request has overtaken.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?
    @ObservationIgnored private var statsStart = CACurrentMediaTime()
    @ObservationIgnored private var statsFrames = 0
    @ObservationIgnored private var statsCost = 0.0

    private struct Request: Equatable {
        let displayID: CGDirectDisplayID
        let source: CGRect
        let scale: CGFloat
        let rate: Int
    }

    init() {
        // The tuning switches live in user defaults, outside the settings the panel observes.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        }
    }

    /// - Parameters:
    ///   - displayFrame: The display's frame in AppKit global coordinates.
    ///   - rect: The panel's resting window frame in AppKit global coordinates.
    func configure(displayID: CGDirectDisplayID, displayFrame: CGRect, rect: CGRect, scale: CGFloat, active: Bool) {
        self.displayID = displayID; self.displayFrame = displayFrame
        self.rect = rect; self.scale = scale; styleActive = active
        reconcile()
    }

    /// A hidden dock captures nothing.
    func setVisible(_ visible: Bool) {
        guard self.visible != visible else { return }
        self.visible = visible
        reconcile()
    }

    func stop() {
        stopped = true
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
        defaultsObserver = nil
        reconcile()
    }

    private func reconcile() {
        let defaults = UserDefaults.standard
        let wanted = !stopped && styleActive && visible && defaults.bool(forKey: DockIceTuning.refractionKey)
            && !rect.isEmpty && CGPreflightScreenCaptureAccess()
        guard wanted else { end(); return }
        let saved = defaults.double(forKey: DockIceTuning.refractionRateKey)
        let rate = Int(min(60, max(5, saved == 0 ? DockIceTuning.refractionRateDefault : saved)))
        // ScreenCaptureKit wants a display-local rectangle measured from the top-left corner.
        let source = CGRect(x: rect.minX - displayFrame.minX, y: displayFrame.maxY - rect.maxY,
                            width: rect.width, height: rect.height)
        let request = Request(displayID: displayID, source: source, scale: scale, rate: rate)
        guard request != running else { return }
        if let stream, running?.displayID == displayID {
            running = request
            let configuration = Self.configuration(request)
            Task { try? await stream.updateConfiguration(configuration) }
        } else {
            end()
            running = request
            begin(request)
        }
    }

    private static func configuration(_ request: Request) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = request.source
        configuration.width = max(1, Int((request.source.width * request.scale).rounded()))
        configuration.height = max(1, Int((request.source.height * request.scale).rounded()))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(request.rate))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.showsCursor = false
        configuration.queueDepth = 3
        return configuration
    }

    private func begin(_ request: Request) {
        generation += 1
        let token = generation
        let output = DockIceBackdropOutput { [weak self] image, cost in
            Task { @MainActor [weak self] in self?.receive(image, cost: cost, token: token) }
        }
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard token == generation,
                      let display = content.displays.first(where: { $0.displayID == request.displayID }) else { return }
                // Excluding the whole app keeps the dock, its tooltips, and its popovers out of
                // the picture; capturing the dock itself would feed the blocks their own image.
                let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
                let stream = SCStream(filter: filter, configuration: Self.configuration(running ?? request), delegate: nil)
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
                try await stream.startCapture()
                guard token == generation else {
                    try? await stream.stopCapture()
                    return
                }
                self.stream = stream
                self.output = output
            } catch {
                if token == generation { running = nil }
            }
        }
    }

    private func end() {
        generation += 1
        running = nil
        output = nil
        if frame != nil { frame = nil }
        DockIceBackdropStats.shared.clear()
        guard let stream else { return }
        self.stream = nil
        Task { try? await stream.stopCapture() }
    }

    private func receive(_ image: CGImage, cost: Double, token: Int) {
        guard token == generation, let running else { return }
        frame = Frame(image: image, scale: running.scale)
        statsFrames += 1
        statsCost += cost
        let now = CACurrentMediaTime()
        guard now - statsStart >= 1 else { return }
        DockIceBackdropStats.shared.report(framesPerSecond: Int((Double(statsFrames) / (now - statsStart)).rounded()),
                                           conversionMilliseconds: statsCost / Double(statsFrames))
        statsStart = now; statsFrames = 0; statsCost = 0
    }
}

/// What the capture is costing, for the tuning card. One shared readout; with several docks it
/// shows whichever reported last.
@MainActor @Observable
final class DockIceBackdropStats {
    static let shared = DockIceBackdropStats()
    private(set) var framesPerSecond: Int?
    private(set) var conversionMilliseconds = 0.0

    func report(framesPerSecond: Int, conversionMilliseconds: Double) {
        self.framesPerSecond = framesPerSecond
        self.conversionMilliseconds = conversionMilliseconds
    }

    func clear() {
        if framesPerSecond != nil { framesPerSecond = nil }
    }
}

/// Receives frames on its own queue and turns each into an image before hopping to the main actor.
private nonisolated final class DockIceBackdropOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "DockIceBackdrop", qos: .userInteractive)
    private let handler: @Sendable (CGImage, Double) -> Void

    init(handler: @escaping @Sendable (CGImage, Double) -> Void) { self.handler = handler }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // The stream also delivers idle and blank notifications that carry no new pixels.
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue,
              let buffer = sampleBuffer.imageBuffer else { return }
        let start = CACurrentMediaTime()
        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &image)
        guard let image else { return }
        handler(image, (CACurrentMediaTime() - start) * 1000)
    }
}
