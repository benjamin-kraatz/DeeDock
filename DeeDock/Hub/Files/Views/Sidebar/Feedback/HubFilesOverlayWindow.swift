import AppKit
import SwiftUI

/// A transparent, click-through window that draws transient sidebar feedback in screen space:
/// the lifted row while reordering, the action label under a drag, the poof, and the folder that
/// flies into the sidebar.
///
/// Feedback lives in its own window because it must follow the pointer past the Hub's edge (a row
/// dragged out to be removed) and draw above the Hub panel. The window never becomes key or main
/// and ignores the mouse, so it can't take focus from the Hub or catch a click.
@MainActor
final class HubFilesOverlayWindow {
    private let panel: NSPanel
    private let host: NSHostingView<AnyView>

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        // Above the Hub (a floating panel when anchored) and the dock; below the system drag image.
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        host = NSHostingView(rootView: AnyView(EmptyView()))
        host.sizingOptions = []
        panel.contentView = host
    }

    var isVisible: Bool { panel.isVisible }
    var frame: CGRect { panel.frame }

    /// Shows `content` filling `frame` (AppKit screen coordinates).
    func show(_ content: some View, frame: CGRect) {
        host.rootView = AnyView(content)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    /// Replaces the content without moving the window.
    func update(_ content: some View) {
        host.rootView = AnyView(content)
    }

    /// Moves the window to `frame` (screen coordinates), immediately or animated over `duration`.
    func move(to frame: CGRect, duration: TimeInterval = 0, completion: (@MainActor () -> Void)? = nil) {
        guard duration > 0 else {
            panel.setFrame(frame, display: true)
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0.9, 0.35, 1)
            panel.animator().setFrame(frame, display: true)
        } completionHandler: {
            MainActor.assumeIsolated { completion?() }
        }
    }

    func hide() {
        panel.orderOut(nil)
        host.rootView = AnyView(EmptyView())
    }
}
