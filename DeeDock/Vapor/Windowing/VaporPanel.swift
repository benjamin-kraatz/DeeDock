import AppKit
import SwiftUI

/// A borderless, non-activating floating panel for Vapor's orb, panel, bubbles and callout.
///
/// It is on every Space and over full-screen apps, is skipped by window cycling, and is never
/// key or main: clicking it never activates DOKK, so Finder stays in front.
final class VaporPanel: NSPanel {
    init(size: CGSize = CGSize(width: 10, height: 10)) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosts SwiftUI in a Vapor panel and takes the first click without activating DOKK.
///
/// Reports when the SwiftUI content's ideal size changes, so the window can be resized and
/// re-placed. The report is deferred to the next main-queue turn to stay out of layout.
final class VaporHostingView<Content: View>: NSHostingView<Content> {
    var intrinsicSizeChanged: (() -> Void)?
    private var reportQueued = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        guard intrinsicSizeChanged != nil, !reportQueued else { return }
        reportQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reportQueued = false
            self.intrinsicSizeChanged?()
        }
    }
}
