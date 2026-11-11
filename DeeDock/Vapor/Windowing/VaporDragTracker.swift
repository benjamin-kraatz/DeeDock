import AppKit

/// Follows file drags anywhere on screen, so the orb can lean toward one before it arrives.
///
/// `NSDraggingDestination` only hears about drags over Vapor's own windows. To report proximity
/// from further away, this watches left-mouse drags with a global and a local event monitor
/// (mouse monitors need no Accessibility trust). A drag counts as a file drag when the drag
/// pasteboard changed since the mouse went down and carries file URLs; that is checked once per
/// drag, not on every event. Monitors exist only between `start()` and `stop()`.
@MainActor
final class VaporDragTracker {
    /// The pointer of an in-flight file drag in global coordinates, or nil when it ends.
    var changed: ((CGPoint?) -> Void)?

    private var monitors: [Any] = []
    private var changeCountAtPress: Int?
    private var isFileDrag: Bool?

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handle(type) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event.type)
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        reset()
    }

    private func handle(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown:
            changeCountAtPress = NSPasteboard(name: .drag).changeCount
            isFileDrag = nil
        case .leftMouseDragged:
            if isFileDrag == nil {
                let pasteboard = NSPasteboard(name: .drag)
                guard let start = changeCountAtPress, pasteboard.changeCount != start else { return }
                isFileDrag = pasteboard.types?.contains(.fileURL) == true
            }
            if isFileDrag == true { changed?(NSEvent.mouseLocation) }
        case .leftMouseUp:
            if isFileDrag == true { changed?(nil) }
            reset()
        default:
            break
        }
    }

    private func reset() {
        changeCountAtPress = nil
        isFileDrag = nil
    }
}
