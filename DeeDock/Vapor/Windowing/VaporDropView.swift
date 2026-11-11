import AppKit

/// Reads the file URLs a drag carries.
enum VaporDragPasteboard {
    static func fileURLs(_ pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
    }
}

/// A container that accepts file drags (`NSDraggingDestination` for `.fileURL`) and reports
/// where they are in AppKit global coordinates. Used for the orb and the open panel.
///
/// Any file drag is accepted as a copy so a refused drop can still shake the orb with its
/// reason; `performDragOperation` returns false when nothing was added, so Finder slides the
/// icons back.
class VaporDropView: NSView {
    /// The drag moved to a point in global coordinates, or left (nil).
    var dragMoved: ((CGPoint?) -> Void)?
    /// The drop landed. Returns whether anything was added.
    var dropped: (([URL]) -> Bool)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        report(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        report(sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        dragMoved?(nil)
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        dragMoved?(nil)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = VaporDragPasteboard.fileURLs(sender.draggingPasteboard)
        dragMoved?(nil)
        guard !urls.isEmpty else { return false }
        return dropped?(urls) ?? false
    }

    private func report(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self],
                                                      options: [.urlReadingFileURLsOnly: true]),
              let window else { return [] }
        dragMoved?(window.convertPoint(toScreen: sender.draggingLocation))
        return .copy
    }
}
