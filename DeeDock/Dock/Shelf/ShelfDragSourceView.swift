import AppKit
import SwiftUI

/// Drags staged items out of the Shelf as ordinary file references.
///
/// The session writes plain `.fileURL` items, so Finder and every other application receive exactly
/// what they would from a Finder drag. It also writes a private type naming the staged items, which
/// only DeeDock reads: it is what lets the dock tell "this chip came from the Shelf" from "these are
/// files from Finder", so dropping a staged item on Trash removes the reference instead of trashing
/// the file.
///
/// Security scope is held for the whole session and released only once AppKit reports it ended.
@MainActor
final class ShelfDragSession: NSObject, NSDraggingSource {
    static let pasteboardType = NSPasteboard.PasteboardType(
        "de.benjaminkraatz.DeeDock.shelf-drag"
    )

    private let accesses: [ShelfResourceAccess]
    private let completed: (Bool) -> Void
    /// Held until AppKit finishes, so neither the session nor its file access is collected early.
    private var retained: ShelfDragSession?

    private init(accesses: [ShelfResourceAccess], completed: @escaping (Bool) -> Void) {
        self.accesses = accesses
        self.completed = completed
    }

    /// Returns false when nothing could be resolved, so the caller can report it.
    @discardableResult
    static func begin(accesses: [ShelfResourceAccess], ids: [UUID], icons: [NSImage],
                      from view: NSView, event: NSEvent,
                      completed: @escaping (Bool) -> Void) -> Bool {
        guard !accesses.isEmpty else { return false }
        let session = ShelfDragSession(accesses: accesses, completed: completed)
        let origin = view.convert(event.locationInWindow, from: nil)
        var items: [NSDraggingItem] = []
        for (index, access) in accesses.enumerated() {
            let pasteboard = NSPasteboardItem()
            pasteboard.setString(access.url.absoluteString, forType: .fileURL)
            if index == 0 {
                pasteboard.setString(ids.map(\.uuidString).joined(separator: ","),
                                     forType: Self.pasteboardType)
            }
            let item = NSDraggingItem(pasteboardWriter: pasteboard)
            let icon = index < icons.count
                ? icons[index]
                : NSWorkspace.shared.icon(forFile: access.url.path)
            let size = DockDragGeometry.imageSize
            // Fan the icons slightly so a multi-item drag reads as a stack, not one file.
            let offset = CGFloat(min(index, 4)) * 6
            item.setDraggingFrame(
                CGRect(x: origin.x - size / 2 + offset,
                       y: origin.y - size / 2 - offset,
                       width: size, height: size),
                contents: icon
            )
            items.append(item)
        }
        let dragging = view.beginDraggingSession(with: items, event: event, source: session)
        dragging.animatesToStartingPositionsOnCancelOrFail = true
        session.retained = session
        return true
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .move]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        let accepted = !operation.intersection([.copy, .move, .delete]).isEmpty
        withExtendedLifetime(accesses) { completed(accepted) }
        retained = nil
    }
}

/// Native mouse tracking for one row in the Shelf panel.
///
/// Selection happens on press, matching a Finder list, so a drag that starts on an already
/// selected row carries the whole selection. A press inside a multiple selection defers its
/// collapse to mouse-up, which is what makes that drag possible at all.
struct ShelfItemDragSourceView: NSViewRepresentable {
    let id: UUID
    let enabled: Bool
    let press: (Bool, Bool) -> Void
    let click: () -> Void
    let cancelClick: () -> Void
    let open: () -> Void
    let begin: (NSView, NSEvent) -> Void

    func makeNSView(context: Context) -> SourceView { SourceView() }
    func updateNSView(_ view: SourceView, context: Context) {
        view.enabled = enabled
        view.press = press
        view.click = click
        view.cancelClick = cancelClick
        view.open = open
        view.begin = begin
    }
    static func dismantleNSView(_ view: SourceView, coordinator: ()) { view.stop() }

    final class SourceView: NSView {
        var enabled = true
        var press: ((Bool, Bool) -> Void)?
        var click: (() -> Void)?
        var cancelClick: (() -> Void)?
        var open: (() -> Void)?
        var begin: ((NSView, NSEvent) -> Void)?
        private var stopped = false
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func isAccessibilityElement() -> Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, event.type == .leftMouseDown,
                  !event.modifierFlags.contains(.control) else { return nil }
            return super.hitTest(point)
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            // AppKit reports the running click count, so the second press opens.
            if event.clickCount >= 2, !event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.shift) {
                cancelClick?()
                if enabled { open?() }
                return
            }
            press?(event.modifierFlags.contains(.command),
                   event.modifierFlags.contains(.shift))
            let origin = event.locationInWindow
            while !stopped, let next = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp, .keyDown],
                until: .distantFuture, inMode: .eventTracking, dequeue: true
            ) {
                if next.type == .keyDown {
                    if next.keyCode == 53 { cancelClick?(); return }
                    continue
                }
                if next.type == .leftMouseUp {
                    if bounds.contains(convert(next.locationInWindow, from: nil)) { click?() }
                    else { cancelClick?() }
                    return
                }
                guard enabled else { continue }
                if hypot(next.locationInWindow.x - origin.x,
                         next.locationInWindow.y - origin.y) >= DockDragGeometry.startDistance {
                    cancelClick?()
                    begin?(self, next)
                    return
                }
            }
        }

        func stop() {
            stopped = true
            press = nil; click = nil; cancelClick = nil; open = nil; begin = nil
        }
    }
}

/// Rubber-band selection over the Shelf list.
///
/// It sits above the rows but declines every point inside a row, so rows keep their own clicks and
/// only empty space starts a sweep. Its coordinates are flipped to match the SwiftUI space the row
/// rectangles were measured in.
struct ShelfSelectionOverlayView: NSViewRepresentable {
    let rowFrames: [UUID: CGRect]
    let began: (Bool) -> Void
    let sweep: (CGRect, Bool) -> Void
    let ended: () -> Void
    let clear: () -> Void

    func makeNSView(context: Context) -> SweepView { SweepView() }
    func updateNSView(_ view: SweepView, context: Context) {
        view.rowFrames = rowFrames
        view.began = began
        view.sweep = sweep
        view.ended = ended
        view.clear = clear
    }
    static func dismantleNSView(_ view: SweepView, coordinator: ()) { view.stop() }

    final class SweepView: NSView {
        var rowFrames: [UUID: CGRect] = [:]
        var began: ((Bool) -> Void)?
        var sweep: ((CGRect, Bool) -> Void)?
        var ended: (() -> Void)?
        var clear: (() -> Void)?
        private var stopped = false
        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func isAccessibilityElement() -> Bool { false }

        /// The trailing strip the scroller occupies. Sweeping must never take it over, or the
        /// list becomes impossible to scroll by dragging.
        private var scrollerInset: CGFloat {
            NSScroller.scrollerWidth(for: .regular, scrollerStyle: NSScroller.preferredScrollerStyle)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, event.type == .leftMouseDown,
                  !event.modifierFlags.contains(.control) else { return nil }
            let local = convert(point, from: superview)
            guard local.x <= bounds.maxX - scrollerInset else { return nil }
            // Rows own their own presses; only the space between and around them sweeps.
            guard !rowFrames.values.contains(where: { $0.contains(local) }) else { return nil }
            return super.hitTest(point)
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            let additive = event.modifierFlags.contains(.command)
                || event.modifierFlags.contains(.shift)
            let origin = convert(event.locationInWindow, from: nil)
            var sweeping = false
            defer { if sweeping { ended?() } }
            while !stopped, let next = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp, .keyDown],
                until: .distantFuture, inMode: .eventTracking, dequeue: true
            ) {
                if next.type == .keyDown {
                    if next.keyCode == 53 { return }
                    continue
                }
                if next.type == .leftMouseUp {
                    // A press on empty space that never moved is a deliberate deselect.
                    if !sweeping, !additive { clear?() }
                    return
                }
                let point = convert(next.locationInWindow, from: nil)
                if !sweeping {
                    guard hypot(point.x - origin.x, point.y - origin.y)
                        >= DockDragGeometry.startDistance else { continue }
                    sweeping = true
                    began?(additive)
                }
                sweep?(ShelfSelection.band(from: origin, to: point), additive)
            }
        }

        func stop() {
            stopped = true
            began = nil; sweep = nil; ended = nil; clear = nil
        }
    }
}
