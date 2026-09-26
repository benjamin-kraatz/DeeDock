import AppKit

/// App-wide owner of the markup window. One markup is open at a time.
///
/// A new request replaces an untouched markup. One with marks on it stays, comes forward, and says
/// so, because replacing it would discard work the user has not exported yet.
@MainActor
final class WindowMarkupController {
    private let thumbnails: any WindowThumbnailServicing
    private var panel: WindowMarkupPanelController?
    /// Set by the dock coordinator: stages a saved file on the Shelf, returning how many did not fit.
    var stageOnShelf: ((URL) throws -> Int)?

    init(thumbnails: any WindowThumbnailServicing) {
        self.thumbnails = thumbnails
    }

    var isOpen: Bool { panel != nil }

    func show(_ request: WindowMarkupRequest) {
        if let panel {
            if panel.session.document.hasMarks {
                panel.front()
                panel.session.show(.init(message: .markupNoticeBusy, symbol: "pencil.and.outline", kind: .failure))
                return
            }
            panel.close()
            self.panel = nil
        }
        let session = WindowMarkupSession(request: request, thumbnails: thumbnails)
        session.stageOnShelf = stageOnShelf
        let frame = WindowMarkupLayout.panelFrame(documentSize: session.document.size, visibleFrame: request.visibleFrame)
        let controller = WindowMarkupPanelController(session: session, frame: frame, origin: request.origin)
        controller.didClose = { [weak self, weak controller] in
            guard let self, let controller, panel === controller else { return }
            panel = nil
        }
        panel = controller
        controller.show()
        session.start()
    }

    func stop() {
        panel?.close()
        panel = nil
        stageOnShelf = nil
    }
}
