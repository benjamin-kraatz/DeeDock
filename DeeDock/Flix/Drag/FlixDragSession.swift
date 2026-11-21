import AppKit

/// A native drag of Flix items: rows, a thread card, or the dock tile.
///
/// Files travel as plain file URLs, so every app receives what a Finder drag would give it; links
/// travel as web URLs, which Finder saves as `.webloc`. A private type lists the item identifiers so
/// DOKK can tell its own drag from a Finder one (the dock tile refuses a drop of its own items).
/// The session reports pointer movement, so the panel can step aside, and its end, with whether the
/// destination accepted it. It keeps itself alive until AppKit ends it.
///
/// Converted upload copies (phase B1) stand in for originals on the pasteboard, because a browser
/// reads the file URLs it is handed. They are meant for that upload only: DOKK's own destinations
/// (the Shelf, the Trash, folder and drive tiles, app tiles, window handoff, Hub Files, Hub Apps,
/// Vapor) map them back to the originals with ``originalURLs(for:on:)`` or ``fileURLs(on:)`` while
/// the drag is in flight, so a temporary copy is never staged, trashed, moved, or copied, and Flix's
/// cleanup of its copies can never delete something DOKK kept.
///
/// The session also keeps the file identity each dragged row listed when the drag began
/// (`FlixItem.fileIdentity`). A row can be stale: the file at its path may have been replaced since
/// Flix Files listed it. DOKK's destructive destinations — the Trash, and folder or drive tiles when
/// they move — ask ``draggedFiles(on:)`` and refuse when the file at a path is no longer the one
/// the row listed (``FlixDraggedFiles/changed(among:)``), so a stale row can never trash or move a
/// replacement. Copies and opens are not checked: they leave the file where it is.
@MainActor
final class FlixDragSession: NSObject, NSDraggingSource {
    static let pasteboardType = NSPasteboard.PasteboardType("de.benjaminkraatz.DeeDock.flix-drag")

    private let moved: (CGPoint) -> Void
    private let ended: (_ accepted: Bool, _ point: CGPoint) -> Void
    private var retained: FlixDragSession?
    /// Each converted copy on the pasteboard, standardized, with the original it stands in for.
    private var originals: [URL: URL] = [:]
    /// The dragged files and the identity each row listed when the drag began.
    private var files: FlixDraggedFiles
    /// The session in flight, if any. One drag at a time is all AppKit allows.
    private(set) static weak var current: FlixDragSession?

    private init(moved: @escaping (CGPoint) -> Void, ended: @escaping (Bool, CGPoint) -> Void,
                 changed: @escaping @MainActor @Sendable ([URL]) -> Void) {
        self.moved = moved
        self.ended = ended
        files = FlixDraggedFiles(identities: [:], reportChanged: changed)
    }

    /// Starts a drag of `items`.
    ///
    /// - Parameters:
    ///   - substitutions: Files to carry instead of an item's own (phase B1's conversions).
    ///   - icons: Drag images by item; the type icon is used when missing.
    ///   - label: A line under the first icon, such as "✦ Upload as PDF · 1.2 MB" (phase B1).
    ///   - moved: Each pointer move, in screen coordinates.
    ///   - ended: Once, with whether a destination took the drop.
    ///   - changed: A destination refused files whose rows are stale (see the type's notes), so the
    ///     rows can take what is at their paths now. May arrive after the drag ended.
    /// - Returns: False when nothing in `items` can be dragged.
    @discardableResult
    static func begin(items: [FlixItem], substitutions: [FlixItem.ID: URL] = [:], icons: [FlixItem.ID: NSImage],
                      label: String? = nil, from view: NSView, event: NSEvent,
                      moved: @escaping (CGPoint) -> Void,
                      ended: @escaping (Bool, CGPoint) -> Void,
                      changed: @escaping @MainActor @Sendable ([URL]) -> Void = { _ in }) -> Bool {
        let draggable = items.filter { substitutions[$0.id] != nil || $0.shareURL != nil }
        guard !draggable.isEmpty else { return false }
        let session = FlixDragSession(moved: moved, ended: ended, changed: changed)
        for item in draggable {
            if let copy = substitutions[item.id], let original = item.url {
                session.originals[copy.standardizedFileURL] = original
            }
            if let path = item.path, item.link == nil {
                session.files.identities[FlixPaths.standardized(path)] = .some(item.fileIdentity)
            }
        }
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
            if index == 0, let label {
                let labelled = FlixDragLabelImage.make(icon: icon, iconSize: size, label: label)
                dragItem.setDraggingFrame(CGRect(x: origin.x - labelled.size.width / 2, y: origin.y - labelled.size.height + size / 2,
                                                 width: labelled.size.width, height: labelled.size.height), contents: labelled)
            } else {
                dragItem.setDraggingFrame(CGRect(x: origin.x - size / 2 + offset, y: origin.y - size / 2 - offset,
                                                 width: size, height: size), contents: icon)
            }
            dragItems.append(dragItem)
        }
        let dragging = view.beginDraggingSession(with: dragItems, event: event, source: session)
        dragging.animatesToStartingPositionsOnCancelOrFail = true
        dragging.draggingFormation = draggable.count > 1 ? .pile : .none
        session.retained = session
        current = session
        return true
    }

    /// `urls` read from a Flix drag's pasteboard, with every converted copy replaced by its
    /// original, for DOKK's own destinations. Any other drag, or one that has ended, is returned
    /// unchanged.
    static func originalURLs(for urls: [URL], on pasteboard: NSPasteboard) -> [URL] {
        guard let current, !current.originals.isEmpty, pasteboard.string(forType: pasteboardType) != nil else { return urls }
        return urls.map { current.originals[$0.standardizedFileURL] ?? $0 }
    }

    /// The file URLs a drag pasteboard carries, with converted copies replaced by their originals:
    /// what every DOKK destination that takes files from a drag reads (Hub Files panes, sidebar,
    /// and pictures search; Hub Apps; Vapor), so a temporary upload copy is never moved, copied,
    /// adopted, or deleted in place of the file the person dragged.
    static func fileURLs(on pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return originalURLs(for: urls, on: pasteboard)
    }

    /// ``originalURLs(for:on:)`` on the drag pasteboard, for SwiftUI drop handlers that receive URLs
    /// without the pasteboard they came from.
    static func originalURLs(forDropped urls: [URL]) -> [URL] {
        originalURLs(for: urls, on: NSPasteboard(name: .drag))
    }

    /// The files of the Flix drag in flight with the identity each row listed, when `pasteboard` is
    /// that drag's; nil for any other drag (Finder's, the Shelf's) and once the drag ended.
    static func draggedFiles(on pasteboard: NSPasteboard) -> FlixDraggedFiles? {
        guard let current, pasteboard.string(forType: pasteboardType) != nil else { return nil }
        return current.files
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

/// The files of one Flix drag, with the identity each row listed when the drag began, so a
/// destination that removes or moves files can tell a stale row from the file it listed.
nonisolated struct FlixDraggedFiles: Sendable {
    /// Standardized paths of the dragged originals, with the row's identity (nil: the row had none
    /// yet, so it cannot vouch for the file).
    var identities: [String: FlixFileIdentity?]
    /// Tells Flix Files which files a destination refused as changed, so their rows take the
    /// identity of what is at their paths now and the next drag acts on the file as it is.
    var reportChanged: @MainActor @Sendable ([URL]) -> Void = { _ in }

    /// The dragged files among `urls` whose file is not the one the row listed: replaced, rewritten,
    /// gone, or never identified. URLs that are not part of this drag are ignored.
    ///
    /// Reads each path with `lstat` (``FlixFileIdentity/of(_:)``), so call it off the main actor: on
    /// a share that went away a single `lstat` can wait for seconds.
    func changed(among urls: [URL]) -> [URL] {
        urls.filter { url in
            guard let listed = identities[FlixPaths.standardized(url.path)] else { return false }
            guard let listed else { return true }
            return !listed.matches(url)
        }
    }
}

/// An error a destination reports when a Flix drag carried a file that changed since its row was
/// listed (``FlixDraggedFiles/changed(among:)``). Its message names the first such file.
nonisolated struct FlixDraggedFileChanged: LocalizedError, Sendable {
    let name: String
    var errorDescription: String? { String(localized: .flixDragFileChanged(name)) }
}

/// The first drag icon with a pill under it naming what the drag does ("✦ Upload as PDF · 1.2 MB"),
/// in the intelligence violet the panel uses.
@MainActor
enum FlixDragLabelImage {
    static func make(icon: NSImage, iconSize: CGFloat, label: String) -> NSImage {
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let text = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: NSColor.white])
        let textSize = text.size()
        let pill = CGSize(width: ceil(textSize.width) + 16, height: 20)
        let size = CGSize(width: max(iconSize, pill.width), height: iconSize + 4 + pill.height)
        return NSImage(size: size, flipped: true) { _ in
            icon.draw(in: CGRect(x: (size.width - iconSize) / 2, y: 0, width: iconSize, height: iconSize))
            let rect = CGRect(x: (size.width - pill.width) / 2, y: iconSize + 4, width: pill.width, height: pill.height)
            NSColor(red: 0.545, green: 0.424, blue: 1, alpha: 0.95).setFill()
            NSBezierPath(roundedRect: rect, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
            text.draw(at: CGPoint(x: rect.minX + 8, y: rect.minY + (pill.height - textSize.height) / 2))
            return true
        }
    }
}
