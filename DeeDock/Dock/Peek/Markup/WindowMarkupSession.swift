import AppKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// Everything a markup needs from Peek to open: the window, its app, a quick picture, and where it
/// should appear to come from.
struct WindowMarkupRequest {
    let window: ApplicationWindowSummary
    let appName: String
    let appIcon: NSImage?
    /// The Peek thumbnail or the enlarged preview's capture; shown until the sharp capture arrives.
    let preview: CGImage?
    /// The enlarged preview's frame in AppKit screen coordinates, when the request came from a staged
    /// hero. The editor's picture starts there so the hand-off reads as one object moving.
    let origin: CGRect?
    /// The usable area of the display the markup opens on.
    let visibleFrame: CGRect
    let backingScale: CGFloat
    let settings: DockSettings
    /// Whether the Shelf tile is on, so **Send to Shelf** is only offered when it can be seen.
    let shelfAvailable: Bool
}

/// Sharpness of the picture on the canvas.
nonisolated enum WindowMarkupCaptureState: Equatable, Sendable {
    /// The preview is showing while the full-resolution capture is on its way.
    case capturing
    /// The sharp capture is showing; the date is when it was taken.
    case fresh(Date)
    /// No sharp capture is possible (minimized window, no permission, capture failed); the preview stays.
    case previewOnly
}

/// A short confirmation or failure shown over the picture.
nonisolated struct WindowMarkupNotice: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case success, failure }
    let message: LocalizedStringResource
    let symbol: String
    let kind: Kind

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.message.key == rhs.message.key && lhs.symbol == rhs.symbol && lhs.kind == rhs.kind
    }
}

/// One markup editing session: the capture, the document, and the actions that leave it.
///
/// The session never writes anything on its own. Copy, Save, Send to Shelf, and drag are each an
/// explicit user action, and Save goes through the system panel. Task ownership: one capture and
/// one recognition task exist at a time; `stop()` cancels both.
@MainActor @Observable
final class WindowMarkupSession {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DeeDock", category: "WindowMarkup")

    let window: ApplicationWindowSummary
    let appName: String
    let appIcon: NSImage?
    let title: String
    let document: WindowMarkupDocument
    let settings: DockSettings
    let shelfAvailable: Bool
    /// The picture on the canvas: the preview first, then the sharp capture.
    private(set) var image: CGImage?
    private(set) var pixelated: CGImage?
    private(set) var captureState: WindowMarkupCaptureState = .capturing
    private(set) var notice: WindowMarkupNotice?
    /// Recognised text of the whole picture, filled on demand by Copy Text or Search Web.
    private(set) var recognizing = false
    /// The accent the presentation frame uses, taken from the app icon.
    let tint: Color
    /// Set by the panel: the window the save panel attaches to.
    @ObservationIgnored var hostWindow: (() -> NSWindow?)?
    /// Set by the coordinator: stages a saved file on the Shelf, returning how many did not fit.
    @ObservationIgnored var stageOnShelf: ((URL) throws -> Int)?
    /// Set by the Live Text view: the overlay's current text selection, if any.
    @ObservationIgnored var liveTextSelection: (() -> String?)?
    private let thumbnails: any WindowThumbnailServicing
    private var captureTask: Task<Void, Never>?
    private var pixelationTask: Task<Void, Never>?
    private var recognitionTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var stopped = false

    init(request: WindowMarkupRequest, thumbnails: any WindowThumbnailServicing) {
        window = request.window
        appName = request.appName
        appIcon = request.appIcon
        title = ApplicationContextMenuProjection.windowTitle(request.window,
                                                             untitled: String(localized: .applicationMenuUntitledWindow))
        settings = request.settings
        shelfAvailable = request.shelfAvailable
        self.thumbnails = thumbnails
        image = request.preview
        document = WindowMarkupDocument(size: Self.documentSize(window: request.window, preview: request.preview,
                                                                backingScale: request.backingScale))
        tint = request.appIcon.flatMap {
            DockIconAccent.surface(for: $0, identity: request.appName, dark: false)
        } ?? .indigo
    }

    /// The document space: the window at full backing resolution, so the export is as sharp as the
    /// screen. Falls back to the preview's own pixels when the window's frame is unknown.
    nonisolated static func documentSize(window: ApplicationWindowSummary, preview: CGImage?, backingScale: CGFloat) -> CGSize {
        if let frame = window.frame, frame.width > 1, frame.height > 1 {
            let scale = max(1, backingScale)
            return CGSize(width: (frame.width * scale).rounded(), height: (frame.height * scale).rounded())
        }
        if let preview { return CGSize(width: preview.width, height: preview.height) }
        return CGSize(width: 1_280, height: 800)
    }

    /// Requests the sharp capture. The preview stays until it arrives; a minimized window keeps it.
    func start() {
        guard !stopped, captureTask == nil else { return }
        guard !window.isMinimized else {
            captureState = .previewOnly
            return
        }
        captureState = .capturing
        let summary = window
        let budget = document.size
        captureTask = Task { @MainActor [weak self, thumbnails] in
            let captured = await thumbnails.capture(summary, fittingPixels: budget)
            guard let self, !Task.isCancelled else { return }
            captureTask = nil
            if let captured {
                image = captured
                captureState = .fresh(.now)
                if document.hasRedactions || document.tool == .redact { preparePixelation() }
            } else {
                captureState = .previewOnly
            }
        }
    }

    /// Replaces the picture with a new capture. Marks stay where they are.
    func recapture() {
        captureTask?.cancel()
        captureTask = nil
        pixelated = nil
        start()
    }

    /// Builds the coarse copy redactions reveal, once per picture, off the main actor.
    func preparePixelation() {
        guard pixelated == nil, pixelationTask == nil, let image else { return }
        let block = document.metrics.pixelBlock
        pixelationTask = Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                WindowMarkupPixelation.pixelated(image, block: block)
            }.value
            guard let self, !Task.isCancelled else { return }
            pixelationTask = nil
            // A recapture may have replaced the picture meanwhile; the next request rebuilds.
            if self.image === image { pixelated = result }
        }
    }

    /// The finished picture: marks, crop, and frame applied, at document resolution.
    func composite() -> CGImage? {
        guard let image else { return nil }
        document.finishText()
        let view = WindowMarkupComposite(image: image, elements: document.elements, metrics: document.metrics,
                                         documentSize: document.size, crop: document.crop, pixelated: pixelated,
                                         framed: document.framed, tint: tint)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(WindowMarkupComposite.outputSize(documentSize: document.size,
                                                                                  crop: document.crop,
                                                                                  framed: document.framed))
        return renderer.cgImage
    }

    // MARK: - Actions

    /// Copies the Live Text selection when there is one, otherwise the finished picture. One
    /// shortcut, ⌘C, therefore does what the user is looking at.
    func copy() {
        if document.liveText, let selection = liveTextSelection?(), !selection.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(selection, forType: .string)
            show(.init(message: .markupNoticeTextCopied, symbol: "checkmark", kind: .success))
            return
        }
        guard let composite = composite(), WindowMarkupExport.copy(composite) else {
            show(.init(message: .markupNoticeCopyFailed, symbol: "exclamationmark.triangle", kind: .failure))
            return
        }
        show(.init(message: .markupNoticeCopied, symbol: "checkmark", kind: .success))
    }

    /// Writes the picture where the user says. The save panel opens in the configured folder.
    func save() {
        guard let composite = composite(), let data = WindowMarkupExport.data(composite, format: settings.windowMarkupFormat) else {
            show(.init(message: .markupNoticeSaveFailed, symbol: "exclamationmark.triangle", kind: .failure))
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [settings.windowMarkupFormat == .png ? .png : .jpeg]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = WindowMarkupExport.suggestedFilename(title: title, appName: appName, at: .now,
                                                                          format: settings.windowMarkupFormat)
        let folder = WindowMarkupFolder.url(configured: settings.windowMarkupFolder)
        if FileManager.default.fileExists(atPath: folder.path) { panel.directoryURL = folder }
        let finish: @MainActor (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
                show(.init(message: .markupNoticeSaved, symbol: "checkmark", kind: .success))
            } catch {
                Self.logger.error("Markup not saved: \(error.localizedDescription, privacy: .public)")
                show(.init(message: .markupNoticeSaveFailed, symbol: "exclamationmark.triangle", kind: .failure))
            }
        }
        // A sheet on a non-activating panel needs the app frontmost, or the save panel takes no keys.
        NSApp.activate(ignoringOtherApps: true)
        if let host = hostWindow?() {
            host.makeKeyAndOrderFront(nil)
            panel.beginSheetModal(for: host) { response in MainActor.assumeIsolated { finish(response) } }
        } else {
            panel.begin { response in MainActor.assumeIsolated { finish(response) } }
        }
    }

    /// Writes the picture into the markup folder and stages that file on the Shelf.
    ///
    /// This is the one action that writes without a panel, because the Shelf holds file references
    /// only. The folder is the one Settings shows, and the notice names the result.
    func sendToShelf() {
        guard let stageOnShelf else { return }
        guard let composite = composite(), let data = WindowMarkupExport.data(composite, format: settings.windowMarkupFormat) else {
            show(.init(message: .markupNoticeSaveFailed, symbol: "exclamationmark.triangle", kind: .failure))
            return
        }
        let folder = WindowMarkupFolder.url(configured: settings.windowMarkupFolder)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let filename = WindowMarkupExport.suggestedFilename(title: title, appName: appName, at: .now,
                                                                format: settings.windowMarkupFormat)
            let url = WindowMarkupExport.uniqueURL(in: folder, filename: filename)
            try data.write(to: url, options: .atomic)
            let rejected = try stageOnShelf(url)
            if rejected > 0 {
                show(.init(message: .markupNoticeShelfFull, symbol: "tray.full", kind: .failure))
            } else {
                show(.init(message: .markupNoticeShelved, symbol: "tray.and.arrow.down", kind: .success))
            }
        } catch {
            Self.logger.error("Markup not shelved: \(error.localizedDescription, privacy: .public)")
            show(.init(message: .markupNoticeShelfFailed, symbol: "exclamationmark.triangle", kind: .failure))
        }
    }

    /// The system share picker for the finished picture, anchored to `rect` in `view`.
    func share(from view: NSView, rect: CGRect) {
        guard let composite = composite() else { return }
        let picker = NSSharingServicePicker(items: [NSImage(cgImage: composite, size: .zero)])
        NSApp.activate(ignoringOtherApps: true)
        picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
    }

    /// A drag payload for the finished picture, built once when the drag starts.
    func dragProvider() -> NSItemProvider? {
        guard let composite = composite(), let png = WindowMarkupExport.data(composite, format: .png) else { return nil }
        return WindowMarkupExport.dragProvider(png: png,
                                               filename: WindowMarkupExport.suggestedFilename(title: title, appName: appName,
                                                                                              at: .now, format: .png))
    }

    /// Copies recognised text: the Live Text selection if there is one, otherwise the crop or picture.
    func copyText() {
        if let selection = liveTextSelection?(), !selection.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(selection, forType: .string)
            show(.init(message: .markupNoticeTextCopied, symbol: "checkmark", kind: .success))
            return
        }
        recognize { [weak self] text in
            guard let self else { return }
            guard let text, !text.isEmpty else {
                show(.init(message: .markupNoticeNoText, symbol: "text.magnifyingglass", kind: .failure))
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            show(.init(message: .markupNoticeTextCopied, symbol: "checkmark", kind: .success))
        }
    }

    /// Opens the configured search engine with the selected or recognised text.
    ///
    /// Pixels never leave the Mac: a true reverse image search would mean uploading the capture to
    /// a third party, and there is no public API for the browser's own image search.
    func searchWeb() {
        if let selection = liveTextSelection?(), !selection.isEmpty {
            open(query: selection)
            return
        }
        recognize { [weak self] text in
            guard let self else { return }
            guard let text, !text.isEmpty else {
                show(.init(message: .markupNoticeNoText, symbol: "text.magnifyingglass", kind: .failure))
                return
            }
            // A page of text is not a query; the first lines carry the subject.
            open(query: text.split(separator: "\n").prefix(3).joined(separator: " "))
        }
    }

    private func open(query: String) {
        guard let url = settings.windowMarkupSearchEngine.url(for: query) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Runs Vision on the crop, or the whole picture, and hands back the transcript.
    private func recognize(_ completion: @escaping @MainActor (String?) -> Void) {
        guard let image else { return completion(nil) }
        recognitionTask?.cancel()
        recognizing = true
        let subject = document.crop.flatMap { image.cropping(to: $0) } ?? image
        recognitionTask = Task { @MainActor [weak self] in
            let text = try? await PeekHistoryRecognizer().recognize(subject)
            guard let self, !Task.isCancelled else { return }
            recognizing = false
            recognitionTask = nil
            completion(text)
        }
    }

    // MARK: - Notices

    func show(_ notice: WindowMarkupNotice) {
        noticeTask?.cancel()
        withAnimation(.spring(duration: 0.35, bounce: 0.2)) { self.notice = notice }
        noticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(notice.kind == .failure ? 2_600 : 1_600))
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { self.notice = nil }
        }
    }

    /// Ends every task. The session is not reused afterwards.
    func stop() {
        stopped = true
        captureTask?.cancel()
        pixelationTask?.cancel()
        recognitionTask?.cancel()
        noticeTask?.cancel()
        captureTask = nil
        pixelationTask = nil
        recognitionTask = nil
        noticeTask = nil
        hostWindow = nil
        stageOnShelf = nil
        liveTextSelection = nil
    }
}
