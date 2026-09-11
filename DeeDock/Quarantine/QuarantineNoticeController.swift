import AppKit
import SwiftUI

/// A nonactivating, click-through notice. A new click replaces the pending dismissal;
/// the notice never steals focus or closes the folder/Shelf panel beneath it.
@MainActor
final class QuarantineNoticeController {
    static let shared = QuarantineNoticeController()
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?

    func show(near anchor: CGRect) {
        dismissal?.cancel()
        panel?.close()
        let content = NSHostingView(rootView: QuarantineNoticeView())
        let size = content.fittingSize
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = content
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) }
        let bounds = screen?.visibleFrame ?? CGRect(origin: anchor.origin, size: size)
        var origin = CGPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + 10)
        if origin.y + size.height > bounds.maxY { origin.y = anchor.minY - size.height - 10 }
        origin.x = min(max(origin.x, bounds.minX + 8), max(bounds.minX + 8, bounds.maxX - size.width - 8))
        origin.y = min(max(origin.y, bounds.minY + 8), max(bounds.minY + 8, bounds.maxY - size.height - 8))
        panel.setFrameOrigin(origin)
        self.panel = panel
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            panel.animator().alphaValue = 1
        }
        NSAccessibility.post(element: NSApp, notification: .announcementRequested, userInfo: [
            .announcement: String(localized: .quarantineNotice),
            .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
        dismissal = Task { [weak self, weak panel] in
            do {
                try await Task.sleep(for: .seconds(2.2))
                guard let panel else { return }
                await NSAnimationContext.runAnimationGroup { context in
                    context.duration = duration
                    panel.animator().alphaValue = 0
                }
                try await Task.sleep(for: .milliseconds(200))
                panel.close()
                if self?.panel === panel { self?.panel = nil }
            } catch { }
        }
    }
}

private struct QuarantineNoticeView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        HStack(spacing: 8) {
            Image("QuarantineInk").resizable().scaledToFit().frame(width: 24, height: 24)
                .accessibilityHidden(true)
            Text(.quarantineNotice).font(.callout).fixedSize()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background {
            if reduceTransparency { Capsule().fill(Color(nsColor: .windowBackgroundColor)) }
        }
        .glassEffect(.regular, in: .capsule)
        .padding(4)
    }
}
