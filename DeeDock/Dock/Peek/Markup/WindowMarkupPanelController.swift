import AppKit
import SwiftUI

private final class WindowMarkupPanel: NSPanel {
    var keyboardHandler: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) {
        if keyboardHandler?(event) != true { super.keyDown(with: event) }
    }
}

/// The first click on an inactive editor should draw, not merely focus the window.
private final class WindowMarkupHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the native window for one markup session.
///
/// A titled panel with a transparent title bar keeps the system close button, resizing, and window
/// dragging while the content draws its own chrome. It is non-activating and becomes key on its
/// own, so typing works without bringing DeeDock's other windows forward; the save sheet and the
/// share picker activate the app themselves when they need to.
@MainActor
final class WindowMarkupPanelController: NSObject, NSWindowDelegate {
    let session: WindowMarkupSession
    private let panel: WindowMarkupPanel
    private var closed = false
    /// Escape with marks on the picture asks for a second press within this window.
    private var discardArmedUntil: Date?
    var didClose: (() -> Void)?

    /// - Parameters:
    ///   - frame: The window frame in AppKit screen coordinates.
    ///   - origin: The enlarged preview's frame in screen coordinates, if the picture should fly from it.
    init(session: WindowMarkupSession, frame: CGRect, origin: CGRect?) {
        self.session = session
        panel = WindowMarkupPanel(contentRect: frame,
                                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
        super.init()
        panel.title = String(localized: .markupWindowTitle(title: session.title))
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.minSize = WindowMarkupLayout.minimumSize
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.keyboardHandler = { [weak self] event in self?.handleKey(event) ?? false }
        // Screen y points up; the content's SwiftUI space points down from the window's top-left.
        let localOrigin = origin.map { rect in
            CGRect(x: rect.minX - frame.minX, y: frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        }
        let hosting = WindowMarkupHostingView(rootView: WindowMarkupEditorView(session: session, origin: localOrigin))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setFrame(frame, display: false)
        session.hostWindow = { [weak panel] in panel }
    }

    func show() {
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 1
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
    }

    func front() { panel.makeKeyAndOrderFront(nil) }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        close()
        return false
    }

    /// Tears the window down. Idempotent; the controller is not reused.
    func close() {
        guard !closed else { return }
        closed = true
        session.stop()
        panel.keyboardHandler = nil
        panel.delegate = nil
        let finish: @MainActor () -> Void = { [panel] in
            panel.orderOut(nil)
            panel.contentView = nil
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || !panel.isVisible {
            finish()
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated { finish() }
            }
        }
        let callback = didClose
        didClose = nil
        callback?()
    }

    /// Unmodified keys the responder chain did not consume: tools, palette, Escape, and Delete.
    /// Command shortcuts live on the SwiftUI buttons so the menus and help show them.
    private func handleKey(_ event: NSEvent) -> Bool {
        let document = session.document
        let plain = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        switch event.keyCode {
        case 53: // Escape
            if document.editingTextID != nil { document.finishText(); return true }
            if document.liveText { document.liveText = false; return true }
            if document.selectedID != nil { document.selectedID = nil; return true }
            if document.tool == .crop, document.crop != nil { document.crop = nil; return true }
            return escapeToClose()
        case 51, 117: // Delete, Forward Delete
            guard plain, document.editingTextID == nil, let id = document.selectedID else { return false }
            document.remove(id)
            return true
        case 36, 76: // Return
            guard plain, document.editingTextID == nil, document.tool == .select, let id = document.selectedID,
                  let element = document.element(id), case .text = element.shape else { return false }
            document.reopenText(id)
            return true
        default:
            break
        }
        guard plain, document.editingTextID == nil, !document.liveText,
              let character = event.charactersIgnoringModifiers?.lowercased().first else { return false }
        if let tool = WindowMarkupTool.allCases.first(where: { $0.key == character }) {
            document.tool = tool
            return true
        }
        if let digit = character.wholeNumberValue, digit >= 1, digit <= WindowMarkupColor.allCases.count {
            document.color = WindowMarkupColor.allCases[digit - 1]
            if let id = document.selectedID { document.restyle(id, color: document.color) }
            return true
        }
        if character == "[" || character == "]" {
            let all = WindowMarkupWeight.allCases
            let index = all.firstIndex(of: document.weight) ?? 1
            document.weight = all[max(0, min(all.count - 1, index + (character == "]" ? 1 : -1)))]
            if let id = document.selectedID { document.restyle(id, weight: document.weight) }
            return true
        }
        return false
    }

    /// Marks are undoable but not saved anywhere, so a first Escape only warns.
    private func escapeToClose() -> Bool {
        if session.document.hasMarks {
            if let armed = discardArmedUntil, armed > .now {
                close()
            } else {
                discardArmedUntil = .now.addingTimeInterval(2.5)
                session.show(.init(message: .markupNoticeEscapeAgain, symbol: "escape", kind: .failure))
            }
        } else {
            close()
        }
        return true
    }
}
