import AppKit
import QuartzCore

/// Window frame changes for the launcher, made without implicit animations.
///
/// AppKit controls hosted by SwiftUI - the pickers, the search field - are real views backed by
/// layers, and a frame change hands those layers an implicit animation. During a presentation the
/// panel's frame is set once, so the resize must not animate anything.
@MainActor
enum LauncherPanelFrame {
    static func set(_ frame: CGRect, on window: NSWindow) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        window.setFrame(frame, display: true)
        NSAnimationContext.endGrouping()
        CATransaction.commit()
    }

    /// The frame the panel holds for the whole presentation: both endpoints of the morph plus room
    /// for the spring to pass the expanded rect, kept on screen.
    static func presentation(origin: CGRect, target: CGRect, screen: CGRect) -> CGRect {
        origin.union(target).insetBy(dx: -overshootRoom, dy: -overshootRoom).intersection(screen)
    }

    private static let overshootRoom: CGFloat = 48
}
