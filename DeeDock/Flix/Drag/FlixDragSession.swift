import AppKit

/// A native drag of Flix items: rows, a thread card, or the dock tile.
///
/// Files travel as plain file URLs, so every app receives what a Finder drag would give it; links
/// travel as web URLs, which Finder saves as `.webloc`. A private type lists the item identifiers so
/// DOKK can tell its own drag from a Finder one (the dock tile refuses a drop of its own items).
/// The session reports pointer movement, so the panel can step aside, and its end, with whether the
/// destination accepted it. It keeps itself alive until AppKit ends it.
@MainActor
final class FlixDragSession: NSObject, NSDraggingSource {
    static let pasteboardType = NSPasteboard.PasteboardType("de.benjaminkraatz.DeeDock.flix-drag")

    private let moved: (CGPoint) -> Void
    private let ended: (_ accepted: Bool, _ point: CGPoint) -> Void
    private var retained: FlixDragSession?
    /// The session in flight, if any. One drag at a time is all AppKit allows.
    private(set) static weak var current: FlixDragSession?

    private init(moved: @escaping (CGPoint) -> Void, ended: @escaping (Bool, CGPoint) -> Void) {
        self.moved = moved
        self.ended = ended
    }

    /// Starts a drag of `items`.
    ///
    /// - Parameters:
    ///   - substitutions: Files to carry instead of an item's own (phase B1's conversions).
    ///   - icons: Drag images by item; the type icon is used when missing.
    ///   - moved: Each pointer move, in screen coordinates.
    ///   - ended: Once, with whether a destination took the drop.
    /// - Returns: False when nothing in `items` can be dragged.
    @discardableResult
    static func begin(items: [FlixItem], substitutions: [FlixItem.ID: URL] = [:], icons: [FlixItem.ID: NSImage],
                      from view: NSView, event: NSEvent,
                      moved: @escaping (CGPoint) -> Void,
                      ended: @escaping (Bool, CGPoint) -> Void) -> Bool {
        let draggable = items.filter { substitutions[$0.id] != nil || $0.shareURL != nil }
        guard !draggable.isEmpty else { return false }
        let session = FlixDragSession(moved: moved, ended: ended)
        let origin = view.convert(event.locationInWindow, from: nil)
        let size: CGFloat = 52
        var dragItems: [NSDraggingItem] = []
        for (index, item) in draggable.enumerated() {
            let pasteboard = NSPasteboardItem()
            if let url = substitutions[item.id] ?? item.url {
                pasteboard.setString(url.absoluteString, forType: .fileURL)
            } else if let link = item.link {
                pasteboard.setString(link.url.absoluteString, forType: .URL)
                pasteboard.setString(link.url.absoluteString, forType: .string)
                if let title = link.title { pasteboard.setString(title, forType: NSPasteboard.PasteboardType("public.url-name")) }
            }
            if index == 0 {
                pasteboard.setString(draggable.map(\.id.uuidString).joined(separator: ","), forType: pasteboardType)
            }
            let dragItem = NSDraggingItem(pasteboardWriter: pasteboard)
            let icon = icons[item.id] ?? FlixIconProvider.typeIcon(for: item)
            // Fan the icons a little so several items read as a stack.
            let offset = CGFloat(min(index, 4)) * 5
            dragItem.setDraggingFrame(CGRect(x: origin.x - size / 2 + offset, y: origin.y - size / 2 - offset,
                                             width: size, height: size), contents: icon)
            dragItems.append(dragItem)
        }
        let dragging = view.beginDraggingSession(with: dragItems, event: event, source: session)
        dragging.animatesToStartingPositionsOnCancelOrFail = true
        dragging.draggingFormation = draggable.count > 1 ? .pile : .none
        session.retained = session
        current = session
        return true
    }

    /// The Flix item identifiers on a pasteboard, empty for any other drag.
    static func itemIDs(on pasteboard: NSPasteboard) -> [UUID] {
        (pasteboard.string(forType: pasteboardType) ?? "").split(separator: ",").compactMap { UUID(uuidString: String($0)) }
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Inside DOKK (a sidebar favorite, a dock tile) the receiver decides; elsewhere behave as
        // Finder does, so Finder moves on the same volume and copies across volumes.
        context == .withinApplication ? [.copy, .move, .generic] : [.copy, .move, .link, .generic]
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        moved(screenPoint)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        ended(!operation.isEmpty, screenPoint)
        retained = nil
        if Self.current === self { Self.current = nil }
    }
}
