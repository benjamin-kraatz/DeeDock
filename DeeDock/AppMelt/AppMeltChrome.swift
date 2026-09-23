import AppKit
import SwiftUI

/// Separate narrow panels leave both source windows fully interactive. A single transparent
/// covering window would intercept their input, so the center is deliberately not a window.
@MainActor final class AppMeltChrome {
    private let pair: AppMeltPair
    private weak var controller: AppMeltController?
    private var panels: [NSPanel] = []
    private let introduction = AppMeltReveal()
    private var focusObservers: [NSObjectProtocol] = []

    /// Closing a toolbar popover can return key focus to this nonactivating panel while
    /// the source app temporarily exposes no AX focused window. This is still pair focus.
    var ownsKeyWindow: Bool {
        panels.contains { panel in
            panel.isVisible && !panel.ignoresMouseEvents
                && (panel.isKeyWindow || panel.attachedSheet?.isKeyWindow == true)
        }
    }

    /// Runs once after native windows accept their layout. Cancellation removes all decoration.
    func reveal() async throws {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            update(show: true)
            return
        }
        introduction.show(frame: pair.frame)
        defer { introduction.stop() }
        do {
            try await Task.sleep(for: .milliseconds(780))
            try Task.checkCancellation()
            panels.forEach { $0.alphaValue = 0 }
            update(show: true)
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                panels.forEach { $0.animator().alphaValue = 1 }
            }, completionHandler: nil)
            introduction.fade()
            try await Task.sleep(for: .milliseconds(250))
            try Task.checkCancellation()
        } catch {
            hide()
            panels.forEach { $0.alphaValue = 1 }
            throw error
        }
    }

    init(pair: AppMeltPair, controller: AppMeltController) {
        self.pair = pair
        self.controller = controller
        pair.replacement = AppMeltWindowPickerState(pair: pair, controller: controller)
        pair.chromeInteractionChanged = { [weak controller, weak pair] in
            guard let pair else { return }
            controller?.refreshAfterTools(pair)
        }
        if pair.applicationIDs.allSatisfy({ $0 == "com.apple.finder" }) {
            pair.finderTools = MeltFinderState(pair: pair, service: controller.service)
            pair.finderTools?.visibilityChanged = { [weak controller, weak pair] in
                guard let pair else { return }
                controller?.refreshAfterTools(pair)
            }
        }
        for index in 0..<6 {
            let panel = AppMeltPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = index == 0
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.fullScreenNone, .transient, .ignoresCycle]
            panel.title = pair.title
            if index == 0 {
                pair.finderTools?.presentationWindow = panel
                panel.contentView = NSHostingView(rootView: AppMeltChromeBar(pair: pair, controller: controller))
            } else if index == 5 {
                panel.contentView = NSHostingView(rootView: AppMeltResizeGrip(pair: pair, controller: controller))
            } else {
                panel.ignoresMouseEvents = true
                panel.contentView = NSHostingView(rootView: AppMeltFrameRail(edge: index))
            }
            panels.append(panel)
            if !panel.ignoresMouseEvents {
                for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
                    focusObservers.append(NotificationCenter.default.addObserver(
                        forName: name, object: panel, queue: .main
                    ) { [weak controller, weak pair] _ in
                        MainActor.assumeIsolated {
                            guard let pair else { return }
                            controller?.refreshAfterTools(pair)
                        }
                    })
                }
            }
        }
    }

    func update(show: Bool) {
        guard show, AppMeltGeometry.mainScreen() != nil else { hide(); return }
        let top = AppMeltGeometry.mainDisplayTop()
        let outer = pair.frame
        // Accepted native sizes can exceed the requested ratio when an app enforces a minimum.
        let members = pair.acceptedFrames.count == 2 ? pair.acceptedFrames
            : AppMeltGeometry.windows(in: outer, ratio: pair.ratio)
        let frames = [
            CGRect(x: outer.minX, y: outer.minY, width: outer.width, height: AppMeltGeometry.header),
            CGRect(x: outer.minX, y: members[0].minY, width: AppMeltGeometry.rim, height: members[0].height),
            CGRect(x: outer.maxX - AppMeltGeometry.rim, y: members[0].minY,
                   width: AppMeltGeometry.rim, height: members[0].height),
            CGRect(x: outer.minX, y: outer.maxY - AppMeltGeometry.rim, width: outer.width, height: AppMeltGeometry.rim),
            CGRect(x: members[0].maxX, y: members[0].minY, width: AppMeltGeometry.divider, height: members[0].height),
            CGRect(x: outer.maxX - 16, y: outer.maxY - 16, width: 16, height: 16)
        ]
        for (panel, frame) in zip(panels, frames) {
            if panel.title != pair.title { panel.title = pair.title }
            panel.setFrame(AppMeltGeometry.appKit(frame, primaryTop: top), display: false)
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
    }

    func hide() {
        pair.replacement?.isPresented = false
        pair.layoutPopover = false
        introduction.stop()
        panels.forEach { $0.orderOut(nil) }
    }

    func stop() {
        pair.replacement?.isPresented = false
        pair.replacement?.cancel()
        focusObservers.forEach { NotificationCenter.default.removeObserver($0) }
        focusObservers.removeAll()
        pair.chromeInteractionChanged = nil
        pair.layoutPopover = false
        pair.finderTools?.dismiss()
        pair.finderTools?.presentationWindow = nil
        introduction.stop()
        panels.forEach { $0.contentView = nil; $0.close() }
        panels.removeAll()
    }
}

private struct AppMeltResizeGrip: View {
    let pair: AppMeltPair
    let controller: AppMeltController
    var body: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 10, weight: .bold))
            .frame(width: 16, height: 16)
            .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: AppMeltGeometry.cornerRadius))
            .overlay {
                AppMeltDragRegion(began: { controller.beginDrag(pair) }, ended: { controller.endDrag(pair) }) { delta in
                    guard pair.isDragging else { return }
                    var frame = pair.pendingFrame ?? pair.frame
                    frame.size.width += delta.width
                    frame.size.height -= delta.height
                    controller.layout(pair, frame: frame)
                }
            }
            .accessibilityLabel(Text(.meltResize))
    }
}

/// Native drag deltas are in global AppKit points and remain stable while the panel moves.
struct AppMeltDragRegion: NSViewRepresentable {
    let began: () -> Void
    let ended: () -> Void
    let moved: (CGSize) -> Void
    func makeNSView(context: Context) -> DragView { DragView(began: began, ended: ended, moved: moved) }
    func updateNSView(_ nsView: DragView, context: Context) {
        nsView.began = began; nsView.ended = ended; nsView.moved = moved
    }

    final class DragView: NSView {
        var began: () -> Void
        var ended: () -> Void
        var moved: (CGSize) -> Void
        private var previous: CGPoint?
        init(began: @escaping () -> Void, ended: @escaping () -> Void, moved: @escaping (CGSize) -> Void) {
            self.began = began; self.ended = ended; self.moved = moved; super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { previous = NSEvent.mouseLocation; began() }
        override func mouseDragged(with event: NSEvent) {
            let point = NSEvent.mouseLocation
            if let previous { moved(CGSize(width: point.x - previous.x, height: point.y - previous.y)) }
            previous = point
        }
        override func mouseUp(with event: NSEvent) { previous = nil; ended() }
    }
}

/// Controls can take keyboard focus after a deliberate click; passive glass rails cannot.
private final class AppMeltPanel: NSPanel {
    override var canBecomeKey: Bool { !ignoresMouseEvents }
    override var canBecomeMain: Bool { false }
}
