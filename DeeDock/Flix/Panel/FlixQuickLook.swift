import AppKit
import QuickLookUI

/// Drives the system Quick Look panel for Flix Files' selection.
///
/// `QLPreviewPanel` asks the key window's responder chain for a controller; the panel's hosting
/// view answers and hands it this object. While Quick Look is key, the Flix panel is not, so the
/// controller tells the panel not to close for it (``isVisible``).
@MainActor
final class FlixQuickLook: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private(set) var urls: [URL] = []
    private var isControlling = false
    /// Keys typed while Quick Look is key, so arrows keep moving the Flix selection.
    var handleKey: (NSEvent) -> Bool = { _ in false }

    var isVisible: Bool {
        isControlling && QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    /// Shows `urls`, or hides the panel when it is showing.
    func toggle(_ urls: [URL], from window: NSWindow?) {
        if isVisible { QLPreviewPanel.shared().orderOut(nil); return }
        guard !urls.isEmpty, let window else { return }
        self.urls = urls
        if let content = window.contentView { window.makeFirstResponder(content) }
        QLPreviewPanel.shared().makeKeyAndOrderFront(nil)
    }

    /// Follows the selection while visible.
    func update(_ urls: [URL]) {
        guard isVisible, urls != self.urls else { return }
        self.urls = urls
        if urls.isEmpty { QLPreviewPanel.shared().orderOut(nil); return }
        QLPreviewPanel.shared().reloadData()
        QLPreviewPanel.shared().currentPreviewItemIndex = 0
    }

    func close() {
        guard isVisible else { return }
        QLPreviewPanel.shared().orderOut(nil)
    }

    func begin(_ panel: QLPreviewPanel) {
        isControlling = true
        panel.dataSource = self
        panel.delegate = self
    }

    func end(_ panel: QLPreviewPanel) {
        isControlling = false
        panel.dataSource = nil
        panel.delegate = nil
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { urls.indices.contains(index) ? urls[index] as NSURL : nil }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        return MainActor.assumeIsolated { handleKey(event) }
    }
}
