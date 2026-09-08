import AppKit

/// A fresh user-driven native drag. Copy is the only offered operation, so a destination cannot
/// negotiate a move or deletion of source files. The source and its grants outlive the panel.
@MainActor
final class WindowFileDragSession: NSObject, NSDraggingSource {
    private let documents: DocumentResourceAccess
    private var retained: WindowFileDragSession?
    private var leaseToken: String?

    private init(_ documents: DocumentResourceAccess) { self.documents = documents }

    static func begin(_ documents: DocumentResourceAccess, from view: NSView, event: NSEvent) {
        guard !documents.urls.isEmpty, documents.urls.count <= WindowFileHandoffController.maximumFiles else { return }
        let source = WindowFileDragSession(documents)
        let point = view.convert(event.locationInWindow, from: nil)
        let items = documents.urls.enumerated().map { index, url in
            let pasteboard = NSPasteboardItem()
            pasteboard.setString(url.absoluteString, forType: .fileURL)
            if index == 0 {
                source.leaseToken = DocumentDragLeaseRegistry.register(documents, on: pasteboard)
            }
            let item = NSDraggingItem(pasteboardWriter: pasteboard)
            let offset = CGFloat(min(index, 4)) * 5
            item.setDraggingFrame(CGRect(x: point.x + offset, y: point.y - offset, width: 36, height: 36),
                                  contents: NSImage(systemSymbolName: "doc", accessibilityDescription: nil))
            return item
        }
        source.retained = source
        let session = view.beginDraggingSession(with: items, event: event, source: source)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        DocumentDragLeaseRegistry.release(leaseToken)
        leaseToken = nil
        retained = nil
    }
}
