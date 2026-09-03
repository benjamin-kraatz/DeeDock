import AppKit
import SwiftUI

/// A nonactivating dock window that accepts keyboard focus only on explicit request.
final class DockPanel: NSPanel {
    /// Gates key-window eligibility; pointer interaction must leave this false.
    var acceptsKeyboardFocus = false
    /// Returns true when a key event has been consumed by dock navigation.
    var keyboardHandler: ((NSEvent) -> Bool)?
    /// Allows the owner to clear explicit selection when another window takes focus.
    var resignedKey: (() -> Void)?
    override var canBecomeKey: Bool { acceptsKeyboardFocus }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) {
        if keyboardHandler?(event) != true { super.keyDown(with: event) }
    }
    override func resignKey() {
        super.resignKey()
        resignedKey?()
    }
}

/// Allows an app-icon click to work while the dock’s owning app is inactive.
final class DockHostingView<Content: View>: NSHostingView<Content> {
    var dragEntered: ((NSDraggingInfo) -> NSDragOperation)?
    var dragPerformed: ((NSDraggingInfo) -> Bool)?
    var dragExited: (() -> Void)?
    var dragEnded: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { dragEntered?(sender) ?? [] }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { dragEntered?(sender) ?? [] }
    override func draggingExited(_ sender: NSDraggingInfo?) { dragExited?() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !(dragEntered?(sender) ?? []).isEmpty }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { dragPerformed?(sender) ?? false }
    override func draggingEnded(_ sender: NSDraggingInfo) { dragEnded?() }
    override func wantsPeriodicDraggingUpdates() -> Bool { true }
}
