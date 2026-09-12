#if DIRECT_DISTRIBUTION
import AppKit
import SwiftUI

/// Owns one nonactivating callout on the main display. Stop removes the panel and timer.
@MainActor
final class UpdateAwarenessController {
    let awareness: UpdateAwarenessStore
    var isBlocked: () -> Bool = { false }
    var targetScreen: () -> NSScreen? = { NSScreen.main }
    var openUpdate: () -> Void = {}
    private var timer: Timer?
    private var panel: UpdateAwarenessPanel?
    private var observers: [NSObjectProtocol] = []

    init(awareness: UpdateAwarenessStore) {
        self.awareness = awareness
    }

    func start() {
        guard timer == nil else { return }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePanel() }
        })
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        closePanel()
        isBlocked = { false }
        targetScreen = { NSScreen.main }
        openUpdate = {}
    }

    private func refresh() {
        let shouldShow = awareness.showsIndicators && awareness.offerVersion != nil && !awareness.windowIsOpen
        if !shouldShow || isBlocked() {
            closePanel()
            return
        }
        guard panel == nil, let version = awareness.offerVersion,
              let screen = targetScreen() ?? NSScreen.main else { return }
        present(version: version, on: screen)
    }

    private func present(version: String, on screen: NSScreen) {
        let panel = UpdateAwarenessPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                         backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.transient, .fullScreenNone]
        panel.isExcludedFromWindowsMenu = true
        let view = NSHostingView(rootView: UpdateAwarenessCalloutView(
            version: version,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
            open: { [weak self] in
                self?.awareness.noteWindowOpened()
                self?.closePanel()
                self?.openUpdate()
            },
            dismiss: { [weak self] in
                self?.awareness.dismiss()
                self?.closePanel()
            }
        ))
        let size = view.fittingSize
        let available = screen.visibleFrame.insetBy(dx: 16, dy: 16)
        panel.setFrame(CGRect(x: available.maxX - size.width, y: available.maxY - size.height,
                              width: size.width, height: size.height), display: false)
        panel.contentView = view
        self.panel = panel
        panel.orderFrontRegardless()
    }

    private func closePanel() {
        panel?.close()
        panel = nil
    }
}

/// Becomes key only through an explicit click, never on presentation or hover.
private final class UpdateAwarenessPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
#endif
