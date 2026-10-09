import AppKit
import QuickLookUI

/// Drives the system Quick Look panel for the Files tab.
///
/// `QLPreviewPanel` asks the responder chain, starting at the key window's first responder, for
/// a controller. `HubFilesQuickLookResponderView` (hosted inside the Files view) answers and
/// hands the panel this object as data source and delegate. Toggling makes that view first
/// responder first so the panel finds it. While the panel is controlled, the Hub holds a
/// `.modal` hold: the panel becomes key, which would otherwise close an anchored Hub.
///
/// The panel zooms out of the item's icon and back into it, as Finder's does: listing views
/// report their icons' frames through ``setSourceFrame(_:for:)`` while they are on screen.
@MainActor
final class HubFilesQuickLook: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    /// The items to preview, in display order. Read each time the panel reloads.
    var items: () -> [URL] = { [] }
    /// Key events typed while the panel is key (arrows move the selection). Returns true when handled.
    var handleKey: (NSEvent) -> Bool = { _ in false }
    /// Begins and ends the hold that keeps an anchored Hub open.
    var setHold: (Bool) -> Void = { _ in }

    /// The hosted responder the panel finds through the responder chain.
    weak var responderView: NSView?

    private var isControlling = false
    private var urls: [URL] = []
    /// Icon frames by file path, in the hosting view's coordinate space (top-left origin, as
    /// SwiftUI's global space reports them). Written on every layout pass, so it is plain storage.
    private var sourceFrames: [String: CGRect] = [:]

    /// Records (or, with nil, forgets) where `url`'s icon is drawn, for the panel's zoom.
    func setSourceFrame(_ frame: CGRect?, for url: URL) {
        let key = FilePathCopy.path(of: url)
        if let frame { sourceFrames[key] = frame } else { sourceFrames.removeValue(forKey: key) }
    }

    /// True while the panel is on screen and showing this tab's items.
    var isVisible: Bool {
        isControlling && QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    /// Shows the panel for the current items, or hides it when it is already showing.
    func toggle() {
        if isVisible {
            QLPreviewPanel.shared().orderOut(nil)
            return
        }
        guard !items().isEmpty, let view = responderView, let window = view.window else { return }
        window.makeFirstResponder(view)
        QLPreviewPanel.shared().makeKeyAndOrderFront(nil)
    }

    /// Hides the panel if this tab controls it.
    func close() {
        guard isVisible else { return }
        QLPreviewPanel.shared().orderOut(nil)
    }

    /// Re-reads the items after the selection changed, so the panel follows arrow keys.
    func selectionDidChange() {
        guard isVisible else { return }
        let next = items()
        guard next != urls else { return }
        if next.isEmpty {
            QLPreviewPanel.shared().orderOut(nil)
            return
        }
        QLPreviewPanel.shared().reloadData()
        QLPreviewPanel.shared().currentPreviewItemIndex = 0
    }

    // MARK: Responder-chain control

    func begin(_ panel: QLPreviewPanel) {
        isControlling = true
        panel.dataSource = self
        panel.delegate = self
        urls = items()
        setHold(true)
    }

    func end(_ panel: QLPreviewPanel) {
        guard isControlling else { return }
        isControlling = false
        panel.dataSource = nil
        panel.delegate = nil
        urls = []
        setHold(false)
    }

    // MARK: QLPreviewPanelDataSource

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated {
            urls = items()
            return urls.count
        }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated {
            urls.indices.contains(index) ? urls[index] as NSURL : nil
        }
    }

    // MARK: QLPreviewPanelDelegate

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        return MainActor.assumeIsolated { handleKey(event) }
    }

    /// The icon's frame on screen, so the panel zooms from and to it. Zero (no zoom) for an item
    /// that is not on screen, for example after arrowing past the visible rows.
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: (any QLPreviewItem)!) -> NSRect {
        MainActor.assumeIsolated {
            guard let url = item.previewItemURL, let frame = sourceFrames[FilePathCopy.path(of: url)],
                  let hosting = responderView?.window?.contentView, let window = hosting.window else { return .zero }
            // The frame is in SwiftUI's global space, which is the hosting view's own (flipped)
            // space; the view converts it to window coordinates, the window to the screen.
            return window.convertToScreen(hosting.convert(frame, to: nil))
        }
    }

    /// The image the panel scales during the zoom: the item's icon, which is what the listing shows.
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, transitionImageFor item: (any QLPreviewItem)!,
                                  contentRect: UnsafeMutablePointer<NSRect>!) -> Any! {
        MainActor.assumeIsolated {
            guard let url = item.previewItemURL else { return nil }
            return HubThumbnailCache.shared.icon(for: url)
        }
    }
}

/// An invisible view that accepts Quick Look panel control for the Files tab.
final class HubFilesQuickLookResponderView: NSView {
    weak var controller: HubFilesQuickLook?

    override var acceptsFirstResponder: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

    // Unhandled keys continue up the responder chain to the Hub's own handling.
    override func keyDown(with event: NSEvent) { nextResponder?.keyDown(with: event) }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { controller != nil }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { controller?.begin(panel) }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { controller?.end(panel) }
}
