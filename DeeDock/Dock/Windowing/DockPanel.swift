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
    override func makeKey() {
        // AppKit can request key status while spring-loading a destination window.
        // Only Focus Dock grants it; forwarding a refused request also emits an AppKit warning.
        guard acceptsKeyboardFocus else { return }
        super.makeKey()
    }
    override func keyDown(with event: NSEvent) {
        if keyboardHandler?(event) != true { super.keyDown(with: event) }
    }
    override func resignKey() {
        super.resignKey()
        resignedKey?()
    }
}

/// Hosts SwiftUI inside a native drag destination. NSHostingView has its own spring-loading
/// eligibility, which can suppress a subclass's AppKit protocol callbacks. The outer NSView
/// owns both native protocols; the child keeps ordinary SwiftUI input and accessibility.
final class DockHostingView<Content: View>: NSView, NSSpringLoadingDestination {
    init(rootView: Content) {
        super.init(frame: .zero)
        let content = DockContentHostingView(rootView: rootView)
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override var isFlipped: Bool { true }
    var dragEntered: ((NSDraggingInfo) -> NSDragOperation)?
    var dragPerformed: ((NSDraggingInfo) -> Bool)?
    var dragExited: (() -> Void)?
    var dragEnded: (() -> Void)?
    var springTarget: ((NSDraggingInfo) -> String?)?
    var springActivate: ((NSDraggingInfo) -> Void)?
    var springHighlight: ((NSDraggingInfo) -> Void)?
    private var springKey: String?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { dragEntered?(sender) ?? [] }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { dragEntered?(sender) ?? [] }
    override func draggingExited(_ sender: NSDraggingInfo?) { springKey = nil; dragExited?() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !(dragEntered?(sender) ?? []).isEmpty }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { dragPerformed?(sender) ?? false }
    override func draggingEnded(_ sender: NSDraggingInfo) { springKey = nil; dragEnded?() }
    override func wantsPeriodicDraggingUpdates() -> Bool { true }

    func springLoadingEntered(_ draggingInfo: any NSDraggingInfo) -> NSSpringLoadingOptions {
        springLoadingUpdated(draggingInfo)
    }
    func springLoadingUpdated(_ draggingInfo: any NSDraggingInfo) -> NSSpringLoadingOptions {
        let key = springTarget?(draggingInfo)
        if key != springKey {
            springKey = key
            draggingInfo.resetSpringLoading()
        }
        return key == nil ? [] : .enabled
    }
    func springLoadingActivated(_ activated: Bool, draggingInfo: any NSDraggingInfo) {
        guard activated, let key = springKey, springTarget?(draggingInfo) == key else { return }
        springActivate?(draggingInfo)
    }
    func springLoadingHighlightChanged(_ draggingInfo: any NSDraggingInfo) { springHighlight?(draggingInfo) }
    func springLoadingExited(_ draggingInfo: any NSDraggingInfo) { springKey = nil; dragExited?() }
}

/// Allows ordinary icon clicks to work while DeeDock is inactive. Native drag destinations
/// belong to the enclosing AppKit view, independently of SwiftUI's spring-loading behavior.
private final class DockContentHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
