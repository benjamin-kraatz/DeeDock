import AppKit
import SwiftUI
import Observation

@MainActor @Observable final class AppMeltProximityOfferState {
    var started = Date()
    var ready = false
    var held = true
    var busy = false
    var names = ""
    var error: LocalizedStringResource?
}

/// Does not activate an app or intercept the pointer until the drag is released.
@MainActor final class AppMeltProximityOffer {
    let state = AppMeltProximityOfferState()
    private var panel: NSPanel?
    var connect: (() -> Void)?
    var dismiss: (() -> Void)?

    func show(near frame: CGRect, names: String) {
        hide()
        state.started = Date(); state.ready = false; state.held = true
        state.busy = false; state.error = nil; state.names = names
        let panel = AppMeltOfferPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false; panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.transient, .fullScreenNone]
        panel.contentView = NSHostingView(rootView: AppMeltProximityOfferView(state: state,
            connect: { [weak self] in self?.connect?() }, dismiss: { [weak self] in self?.dismiss?() }))
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        var rect = AppMeltGeometry.appKit(CGRect(x: frame.midX - 150, y: frame.minY + 56, width: 300, height: 116), primaryTop: top)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) }) {
            rect.origin.x = min(max(rect.minX, screen.visibleFrame.minX), screen.visibleFrame.maxX - rect.width)
            rect.origin.y = min(max(rect.minY, screen.visibleFrame.minY), screen.visibleFrame.maxY - rect.height)
        }
        panel.setFrame(rect, display: false)
        self.panel = panel
        panel.orderFrontRegardless()
    }

    func release() { state.held = false; panel?.ignoresMouseEvents = false }
    func contains(_ point: CGPoint) -> Bool { panel?.frame.contains(point) == true }
    func hide() {
        state.ready = false
        panel?.orderOut(nil); panel?.contentView = nil; panel?.close(); panel = nil
    }
}

private final class AppMeltOfferPanel: NSPanel {
    override var canBecomeKey: Bool { !ignoresMouseEvents }
}

private struct AppMeltProximityOfferView: View {
    let state: AppMeltProximityOfferState
    let connect: () -> Void
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        VStack(spacing: 9) {
            Text(verbatim: state.names).font(.headline).lineLimit(1)
            if let error = state.error { Text(error).font(.caption).lineLimit(2) }
            if !state.ready {
                Text(.meltHoldNearby).font(.caption)
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
                    ProgressView(value: reduceMotion ? 0 : min(1, context.date.timeIntervalSince(state.started) / 1.5))
                }
            } else {
                HStack {
                    Button(.meltDismiss, action: dismiss).keyboardShortcut(.cancelAction)
                    Button(.meltCreate, action: connect).buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(state.held || state.busy)
                    if state.busy { ProgressView().controlSize(.small) }
                }
            }
        }
        .padding(14).frame(width: 300, height: 116)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 18).fill(Color(nsColor: .windowBackgroundColor))
            } else {
                RoundedRectangle(cornerRadius: 18).fill(.regularMaterial)
            }
        }
    }
}
