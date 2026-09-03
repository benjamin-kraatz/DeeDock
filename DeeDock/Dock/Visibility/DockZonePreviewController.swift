import AppKit
import Observation
import SwiftUI

/// Owns one nonactivating, click-through outline and its bounded lifetime; edits do not restart the timeout.
@MainActor @Observable final class DockZonePreviewController {
    var displayID: String? { lease.displayID }
    private let lease: DockPreviewLease
    @ObservationIgnored private var panel: NSPanel?

    init(scheduler: (any DockVisibilityScheduling)? = nil) {
        lease = DockPreviewLease(scheduler: scheduler ?? DockVisibilityScheduler())
        lease.didEnd = { [weak self] in self?.closePanel() }
    }
    func show(displayID: String, geometry: DockPresentationGeometry) {
        stop()
        lease.begin(displayID: displayID)
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.ignoresMouseEvents = true; panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        self.panel = panel
        update(geometry)
        panel.orderFrontRegardless()
    }
    func update(_ geometry: DockPresentationGeometry) {
        guard let panel else { return }
        let frame = geometry.activation.retention
        panel.setFrame(frame, display: true)
        let zone = geometry.activation.zone
        let local = CGRect(x: zone.minX - frame.minX, y: frame.maxY - zone.maxY, width: zone.width, height: zone.height)
        panel.contentView = NSHostingView(rootView: DockZoneOutline(zone: local).frame(width: frame.width, height: frame.height))
    }
    func stop() { lease.stop(); closePanel() }
    private func closePanel() { panel?.close(); panel = nil }
}

/// The blue outline is the trigger; the faint dashed envelope shows the safe pointer route.
private struct DockZoneOutline: View {
    let zone: CGRect
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().strokeBorder(.blue.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            Rectangle().fill(.blue.opacity(0.18))
                .overlay { Rectangle().strokeBorder(.blue, lineWidth: 2) }
                .frame(width: zone.width, height: zone.height).offset(x: zone.minX, y: zone.minY)
        }.accessibilityHidden(true)
    }
}
