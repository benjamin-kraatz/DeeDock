import AppKit
import SwiftUI

/// What one native interaction region does: clicks, a file drag source, a drop target with
/// spring-loading, a context menu, and hover.
///
/// Each callback is optional; a region only takes part in what it configures. Closures run on
/// the main actor from AppKit event handling.
struct HubFilesInteraction {
    /// Mouse-down, before any drag starts. Selection changes happen here.
    var mouseDown: ((NSEvent) -> Void)?
    /// Mouse-up inside the region when no drag started (Finder's deferred "select only this").
    var mouseUp: ((NSEvent) -> Void)?
    /// A second click inside the region.
    var doubleClick: (() -> Void)?
    /// The file URLs to drag, read when the pointer has moved far enough. Nil: not a drag source.
    var dragURLs: (() -> [URL])?
    /// Begins (true) or ends (false) the Hub's `.drag` hold around a drag session.
    var dragHold: ((Bool) -> Void)?
    /// The folder a drop lands in. Nil, or a nil result: not a drop target.
    var dropDestination: (() -> URL?)?
    /// The highlight shown while a valid drag hovers.
    var dropHighlight: HubFilesDropHighlight?
    /// Spring-loading action: open the folder or select the tab after the system dwell.
    var springLoad: (() -> Void)?
    /// Builds the context menu for a secondary click.
    var menu: (() -> NSMenu?)?
    /// Pointer entered (true) or left (false) the region.
    var hoverChanged: ((Bool) -> Void)?
    /// A Favorites row: dragging it reorders it, or removes it past the sidebar's edge.
    var sidebarEntry: HubFilesSidebarEntryID?
    /// Drags over this region go to `HubFilesSidebarModel`, which hit-tests the whole Favorites
    /// list at once instead of trusting whichever row happens to be under the pointer.
    var routesDropsToSidebar = false
}

/// Places a `HubFilesInteractionView` over (or behind) SwiftUI content.
///
/// The region must be part of ordinary hit testing: AppKit finds drag destinations that way, so a
/// region that opted out could not receive drops. It therefore performs clicks itself and the
/// SwiftUI content it covers stays purely visual.
struct HubFilesInteractionRegion: NSViewRepresentable {
    let interaction: HubFilesInteraction
    let model: HubFilesModel

    func makeNSView(context: Context) -> HubFilesInteractionView { HubFilesInteractionView() }

    func updateNSView(_ view: HubFilesInteractionView, context: Context) {
        view.interaction = interaction
        view.model = model
        if interaction.dropDestination != nil || interaction.routesDropsToSidebar {
            view.registerForDraggedTypes([.fileURL])
        } else {
            view.unregisterDraggedTypes()
        }
    }

    static func dismantleNSView(_ view: HubFilesInteractionView, coordinator: ()) { view.stop() }
}

/// The AppKit side of `HubFilesInteractionRegion`.
final class HubFilesInteractionView: NSView, NSDraggingSource, NSSpringLoadingDestination {
    var interaction = HubFilesInteraction()
    weak var model: HubFilesModel?

    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var stopped = false
    /// Retains the view while AppKit owns a drag session that outlives SwiftUI removing the row
    /// (a moved item disappears from the listing before the session ends).
    private var retainedForSession: HubFilesInteractionView?
    private var sessionHold: ((Bool) -> Void)?
    private var cachedSources: (changeCount: Int, urls: [URL])?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func isAccessibilityElement() -> Bool { false }

    func stop() {
        stopped = true
        unregisterDraggedTypes()
        if isHovered { interaction.hoverChanged?(false) }
        interaction = HubFilesInteraction()
    }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func setHovered(_ hovered: Bool) {
        guard hovered != isHovered, !stopped else { return }
        isHovered = hovered
        interaction.hoverChanged?(hovered)
    }

    // MARK: Clicks and drag source

    override func mouseDown(with event: NSEvent) {
        guard !stopped, let window else { return }
        if event.modifierFlags.contains(.control) {
            rightMouseDown(with: event)
            return
        }
        interaction.mouseDown?(event)
        let origin = event.locationInWindow
        // Track until the button comes up or the pointer travels far enough to start a drag,
        // like FolderStackDragSourceView. The loop runs in event-tracking mode, so nothing else
        // reacts to these events.
        while !stopped, let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown],
                                                    until: .distantFuture, inMode: .eventTracking, dequeue: true) {
            if next.type == .keyDown {
                if next.keyCode == 53 { return }
                continue
            }
            if next.type == .leftMouseUp {
                guard bounds.contains(convert(next.locationInWindow, from: nil)) else { return }
                interaction.mouseUp?(event)
                if event.clickCount == 2 { interaction.doubleClick?() }
                return
            }
            let moved = hypot(next.locationInWindow.x - origin.x, next.locationInWindow.y - origin.y)
            guard moved >= DockDragGeometry.startDistance else { continue }
            if let dragURLs = interaction.dragURLs {
                beginDrag(urls: dragURLs(), event: next)
                return
            }
            if let entry = interaction.sidebarEntry, let sidebar = model?.sidebar {
                trackReorder(entry, sidebar: sidebar, window: window)
                return
            }
        }
    }

    private func beginDrag(urls: [URL], event: NSEvent) {
        guard !urls.isEmpty else { return }
        let side = min(bounds.height, 32)
        let start = convert(event.locationInWindow, from: nil)
        // The session carries at most 64 items; the sidebar must act on exactly those.
        let urls = Array(urls.prefix(64))
        let items = urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let offset = CGFloat(min(index, 4)) * 3
            let frame = CGRect(x: start.x - side / 2 + offset, y: start.y - side / 2 + offset, width: side, height: side)
            item.setDraggingFrame(frame, contents: HubThumbnailCache.shared.icon(for: url))
            return item
        }
        sessionHold = interaction.dragHold
        sessionHold?(true)
        retainedForSession = self
        let session = beginDraggingSession(with: Array(items), event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .pile
        model?.sidebar.itemDragBegan(sequence: session.draggingSequenceNumber, urls: urls)
    }

    /// Moves a Favorites row with the pointer until the button comes up (drop or remove) or
    /// Escape (back where it was).
    ///
    /// Runs its own event-tracking loop instead of an `NSDraggingSession`: the row is not a file
    /// drag, and the loop sees every pointer move, inside the Hub or not, so the lifted row, the
    /// poof cursor, and the slot all follow. Lifting hides the row, which dismantles this view;
    /// the loop keeps its own references to the window, the sidebar model, and the sidebar's scroll
    /// view for that reason.
    ///
    /// The loop wakes every frame even without events, to scroll the sidebar while the pointer
    /// rests near its top or bottom edge (a custom tracking loop gets no autoscroll from AppKit).
    /// It ends as soon as the sidebar aborts the session, for example when the Files tab hides.
    private func trackReorder(_ id: HubFilesSidebarEntryID, sidebar: HubFilesSidebarModel, window: NSWindow) {
        let session = sidebar.reorderSession
        let scrollView = enclosingScrollView
        // Starting can wait a frame or two (another row still landing, the list not laid out yet);
        // each move retries until it starts.
        var started = false
        func startIfNeeded() {
            guard !started, sidebar.reorderSession == session, let rowFrame = screenFrame else { return }
            started = sidebar.beginReorder(id, pointer: NSEvent.mouseLocation, rowFrame: rowFrame)
        }
        startIfNeeded()
        if started { sidebar.updateReorder(pointer: NSEvent.mouseLocation) }
        while sidebar.reorderSession == session {
            let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown],
                                        until: Date(timeIntervalSinceNow: 1.0 / 60), inMode: .eventTracking, dequeue: true)
            guard sidebar.reorderSession == session else { return }
            switch next?.type {
            case .keyDown? where next?.keyCode == 53:
                sidebar.cancelReorder()
                return
            case .leftMouseUp?:
                sidebar.endReorder(pointer: NSEvent.mouseLocation)
                return
            case .leftMouseDragged?:
                startIfNeeded()
                if started { sidebar.updateReorder(pointer: NSEvent.mouseLocation) }
            default:
                // A quiet frame: scroll if the pointer rests at an edge, then retarget the slot.
                if started, Self.autoscroll(scrollView, toward: NSEvent.mouseLocation) {
                    sidebar.updateReorder(pointer: NSEvent.mouseLocation)
                }
            }
        }
    }

    /// Scrolls `scrollView` one step when `pointer` (screen) is within its top or bottom 28 pt, or
    /// up to 30 pt beyond it, faster nearer the edge. Returns whether it scrolled.
    private static func autoscroll(_ scrollView: NSScrollView?, toward pointer: CGPoint) -> Bool {
        guard let scrollView, let frame = scrollView.screenFrame,
              pointer.x >= frame.minX, pointer.x <= frame.maxX else { return false }
        let edge: CGFloat = 28, overshoot: CGFloat = 30
        let direction: CGFloat
        let depth: CGFloat
        if pointer.y > frame.maxY - edge, pointer.y <= frame.maxY + overshoot {
            direction = -1
            depth = pointer.y - (frame.maxY - edge)
        } else if pointer.y < frame.minY + edge, pointer.y >= frame.minY - overshoot {
            direction = 1
            depth = (frame.minY + edge) - pointer.y
        } else {
            return false
        }
        let clip = scrollView.contentView
        guard let document = scrollView.documentView else { return false }
        let step = min(2 + depth * 0.35, 14)
        let maxY = max(0, document.frame.height - clip.bounds.height)
        var origin = clip.bounds.origin
        // Toward the end of the list means a larger y in a flipped clip view, a smaller one otherwise.
        // Either way the origin stays within 0...maxY.
        let delta = (clip.isFlipped ? direction : -direction) * step
        origin.y = min(max(origin.y + delta, 0), maxY)
        guard origin.y != clip.bounds.origin.y else { return false }
        clip.scroll(to: origin)
        scrollView.reflectScrolledClipView(clip)
        return true
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? [.copy, .move] : [.copy, .move, .generic]
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { false }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        model?.dropHighlight = nil
        model?.sidebar.itemDragEnded(sequence: session.draggingSequenceNumber)
        sessionHold?(false)
        sessionHold = nil
        retainedForSession = nil
    }

    // MARK: Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        guard !stopped else { return nil }
        return interaction.menu?()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard !stopped, let menu = interaction.menu?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    // MARK: Drop target

    private func destination(for info: NSDraggingInfo) -> URL? {
        guard !stopped, let destination = interaction.dropDestination?() else { return nil }
        return destination
    }

    /// The dragged file URLs, read once per pasteboard change rather than on every pointer move.
    private func sources(_ info: NSDraggingInfo) -> [URL] {
        let pasteboard = info.draggingPasteboard
        if let cachedSources, cachedSources.changeCount == pasteboard.changeCount { return cachedSources.urls }
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        cachedSources = (pasteboard.changeCount, urls)
        return urls
    }

    private func operation(for info: NSDraggingInfo) -> NSDragOperation {
        guard let model, let destination = destination(for: info) else { return [] }
        // DOKK's own dock-item drags carry their own pasteboard type and are not file transfers.
        guard info.draggingPasteboard.string(forType: DockDragCoordinator.pasteboardType) == nil else { return [] }
        return model.dropOperation(sources: sources(info), destination: destination,
                                   optionHeld: NSEvent.modifierFlags.contains(.option),
                                   sourceMask: info.draggingSourceOperationMask)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !stopped, let model else { return [] }
        if interaction.routesDropsToSidebar { return model.sidebar.itemDragUpdated(sender, in: self) }
        model.sidebar.itemDragEntered(sender)
        let result = operation(for: sender)
        if let highlight = interaction.dropHighlight {
            if result.isEmpty { model.clearDropHighlight(highlight) } else { model.dropHighlight = highlight }
        }
        return result
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        if interaction.routesDropsToSidebar { model?.sidebar.itemDragExited() }
        if let highlight = interaction.dropHighlight { model?.clearDropHighlight(highlight) }
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        if let highlight = interaction.dropHighlight { model?.clearDropHighlight(highlight) }
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if interaction.routesDropsToSidebar, let model { return !model.sidebar.itemDragUpdated(sender, in: self).isEmpty }
        return !operation(for: sender).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if interaction.routesDropsToSidebar, let model { return model.sidebar.performItemDrop(sender, in: self) }
        guard let model, let destination = destination(for: sender) else { return false }
        return model.performDrop(sources: sources(sender), destination: destination,
                                 optionHeld: NSEvent.modifierFlags.contains(.option),
                                 sourceMask: sender.draggingSourceOperationMask)
    }

    // MARK: Spring-loading

    func springLoadingEntered(_ draggingInfo: NSDraggingInfo) -> NSSpringLoadingOptions {
        guard interaction.springLoad != nil else { return [] }
        if interaction.routesDropsToSidebar {
            // Only while the drop would land in this row's folder, not while it would insert.
            guard let entry = interaction.sidebarEntry, model?.sidebar.springLoads(entry) == true else { return [] }
            return .enabled
        }
        return !operation(for: draggingInfo).isEmpty ? .enabled : []
    }

    func springLoadingUpdated(_ draggingInfo: NSDraggingInfo) -> NSSpringLoadingOptions {
        springLoadingEntered(draggingInfo)
    }

    func springLoadingActivated(_ activated: Bool, draggingInfo: NSDraggingInfo) {
        guard activated, !stopped else { return }
        interaction.springLoad?()
    }

    func springLoadingHighlightChanged(_ draggingInfo: NSDraggingInfo) {}
}
