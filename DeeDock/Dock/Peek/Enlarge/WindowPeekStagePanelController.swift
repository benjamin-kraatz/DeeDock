import AppKit
import SwiftUI

private final class WindowPeekStagePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns the click-through panel that covers one display for the enlarged preview.
///
/// The panel sits one level above the Peek panel so an exhibit can fly out of its card and over the
/// strip. It ignores the mouse, so tracking areas, hover, and clicks still land on the Peek cards
/// beneath it, and it never takes focus.
@MainActor
final class WindowPeekStagePanelController {
    let stage = WindowPeekStage()
    /// The display frame the panel covers, in AppKit screen coordinates.
    let screenFrame: CGRect
    private let panel: WindowPeekStagePanel

    init(screenFrame: CGRect) {
        self.screenFrame = screenFrame
        panel = WindowPeekStagePanel(contentRect: screenFrame, styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        // The stage must cover the whole display: the dim fills it, and exhibit frames are offsets
        // from its top-left corner. A hosting view that sized the window to its content shrank the
        // panel, which hid the dim and shifted the hero, so the size is fixed on both sides.
        let hosting = NSHostingView(rootView: WindowPeekStageView(stage: stage)
            .frame(width: screenFrame.width, height: screenFrame.height))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setFrame(screenFrame, display: false)
    }

    /// Converts a screen rectangle into the stage view's coordinate space.
    func local(_ rect: CGRect) -> CGRect { WindowPeekEnlargeGeometry.local(rect, in: screenFrame) }

    /// The panel's window level, so companions such as the hero toolbar can sit just above it.
    var level: NSWindow.Level { panel.level }

    func show() {
        panel.alphaValue = 1
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    /// Orders the panel out once nothing is left on stage, unless something was staged meanwhile.
    func hideIfIdle() {
        guard stage.exhibits.isEmpty, !stage.dimmed else { return }
        panel.orderOut(nil)
    }

    /// Ends the stage for good; the controller is not reused afterwards. Peek can close in the same
    /// instant a dismissal starts, so fade rather than cut.
    func close(animated: Bool, duration: TimeInterval = 0.12) {
        let finish: @MainActor () -> Void = { [panel] in
            panel.orderOut(nil)
            panel.contentView = nil
        }
        guard animated, panel.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            finish()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { finish() }
        }
    }
}
