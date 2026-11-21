import AppKit
import Observation
import SwiftUI

/// The pending Unpin Undo shown by ``DockUnpinUndoController``.
@MainActor @Observable
final class DockUnpinUndoModel {
    struct Offer: Equatable {
        let token: UUID
        let appName: String
    }
    var offer: Offer?
}

/// Shows "Unpinned <App> · Undo" beside the source dock for five seconds after a drag-out unpin.
///
/// The toast lives in its own small non-activating panel, so clicking Undo never activates DOKK
/// or takes focus from the front app. A new unpin replaces the offer; Undo, the timeout, and
/// ``stop()`` remove it. The dismissal task is owned here and cancelled with the offer.
@MainActor
final class DockUnpinUndoController {
    static let duration: Duration = .seconds(5)
    private let model = DockUnpinUndoModel()
    private var panel: NSPanel?
    private var undo: (() -> Void)?
    private var dismissal: Task<Void, Never>?

    /// - Parameters:
    ///   - glass: The source dock's resting glass, in AppKit global coordinates.
    ///   - edge: The source dock's screen edge; the toast sits on the inward side of the glass.
    ///   - undo: Restores the pin. Called at most once.
    func show(appName: String, glass: CGRect, edge: DockEdge, undo: @escaping () -> Void) {
        self.undo = undo
        let panel = panel ?? makePanel()
        let size = CGSize(width: 440, height: 64)
        var frame = Self.frame(size: size, glass: glass, edge: edge)
        // A dock near a corner would push part of the toast, and maybe Undo, off its display.
        if let visible = NSScreen.screens.first(where: { $0.frame.intersects(glass) })?.visibleFrame {
            frame = DropPlacementGeometry.clamp(frame, into: visible)
        }
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()
        withAnimation(Self.animation) { model.offer = .init(token: UUID(), appName: appName) }
        dismissal?.cancel()
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: Self.duration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissal?.cancel(); dismissal = nil
        undo = nil
        guard model.offer != nil else { return }
        withAnimation(Self.animation) { model.offer = nil }
        let panel = panel
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            if self.model.offer == nil { panel?.orderOut(nil) }
        }
    }

    func stop() {
        dismissal?.cancel(); dismissal = nil
        undo = nil
        model.offer = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel?.close()
        panel = nil
    }

    private func performUndo() {
        let action = undo
        dismiss()
        action?()
    }

    private static var animation: Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .easeInOut(duration: 0.15)
            : .spring(response: 0.3, dampingFraction: 0.78)
    }

    /// Centered on the glass along its edge, 12 pt inward from it.
    static func frame(size: CGSize, glass: CGRect, edge: DockEdge) -> CGRect {
        switch edge {
        case .bottom: CGRect(x: glass.midX - size.width / 2, y: glass.maxY + 12, width: size.width, height: size.height)
        case .top: CGRect(x: glass.midX - size.width / 2, y: glass.minY - 12 - size.height, width: size.width, height: size.height)
        case .left: CGRect(x: glass.maxX + 12, y: glass.midY - size.height / 2, width: size.width, height: size.height)
        case .right: CGRect(x: glass.minX - 12 - size.width, y: glass.midY - size.height / 2, width: size.width, height: size.height)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 440, height: 64),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let root = DockUnpinUndoToastHost(model: model) { [weak self] in self?.performUndo() }
        let hosting = DockUnpinUndoHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting
        self.panel = panel
        return panel
    }
}

/// Places the toast at the panel's center and animates it in and out.
private struct DockUnpinUndoToastHost: View {
    let model: DockUnpinUndoModel
    let undo: () -> Void

    var body: some View {
        ZStack {
            if let offer = model.offer {
                DockUnpinUndoToast(appName: offer.appName, undo: undo)
                    .id(offer.token)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 12)),
                        removal: .opacity.combined(with: .offset(y: 6))))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Lets the first click on Undo work while DOKK is not the active app.
private final class DockUnpinUndoHostingView: NSHostingView<DockUnpinUndoToastHost> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
