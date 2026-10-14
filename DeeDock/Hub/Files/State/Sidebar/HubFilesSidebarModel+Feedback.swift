import AppKit
import SwiftUI

/// Sizes shared by the sidebar's rows, slots, and overlay feedback.
enum HubFilesSidebarMetrics {
    /// A row's width: the sidebar minus its horizontal padding.
    static let rowWidth: CGFloat = HubFilesMetrics.sidebarWidth - 20
    /// Room around the lifted row for its shadow and the label under it.
    static let overlayInset: CGFloat = 16
    static let overlaySize = CGSize(width: rowWidth + 2 * overlayInset + 60,
                                    height: HubFilesMetrics.rowHeight + 2 * overlayInset + 30)
    /// The gap between the last Favorites row and the end slot.
    static let endSlotSpacing: CGFloat = 3
    /// How far below the last row a drop still inserts at the end.
    static let endZone: CGFloat = 14
    /// The action label's offset from the pointer (screen points, y up): below and to the right,
    /// clear of the system drag image's badge.
    static let labelOffset = CGSize(width: 16, height: -30)
    static let poofSize: CGFloat = 120
    static let flightDuration: Double = 0.54
}

/// The overlay-window feedback: the action label, the lifted row, the poof, and the flight.
extension HubFilesSidebarModel {
    /// Shows `action` under the pointer, or hides the label when there is nothing to name.
    func showLabel(_ action: HubFilesSidebarAction?, at pointer: CGPoint) {
        guard let action else {
            labelWindow.hide()
            return
        }
        let size = CGSize(width: 320, height: 32)
        let frame = CGRect(x: pointer.x + HubFilesSidebarMetrics.labelOffset.width,
                           y: pointer.y + HubFilesSidebarMetrics.labelOffset.height - size.height / 2,
                           width: size.width, height: size.height)
        let content = HubFilesSidebarActionLabel(action: action)
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        if labelWindow.isVisible {
            labelWindow.update(content)
            labelWindow.move(to: frame)
        } else {
            labelWindow.show(content, frame: frame)
        }
    }

    /// Shows the lifted row under the pointer, keeping the offset at which it was grabbed.
    func showLiftedRow(_ entry: HubFilesSidebarEntry, removing: Bool, pointer: CGPoint) {
        guard let drag = reorder else { return }
        let origin = CGPoint(x: pointer.x - drag.grabOffset.width, y: pointer.y - drag.grabOffset.height)
        let frame = Self.liftFrame(rowOrigin: origin, rowSize: drag.rowFrame.size)
        let content = HubFilesSidebarLiftedRow(
            symbolName: Self.symbolName(for: entry), title: store.title(for: entry), isRemoving: removing,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
        if liftWindow.isVisible {
            liftWindow.update(content)
            liftWindow.move(to: frame)
        } else {
            liftWindow.show(content, frame: frame)
        }
    }

    /// The overlay frame that draws a lifted row with its origin at `rowOrigin` (screen, y up).
    /// The row sits `overlayInset` from the window's top-left corner.
    static func liftFrame(rowOrigin: CGPoint, rowSize: CGSize) -> CGRect {
        let size = HubFilesSidebarMetrics.overlaySize
        let inset = HubFilesSidebarMetrics.overlayInset
        return CGRect(x: rowOrigin.x - inset, y: rowOrigin.y + rowSize.height + inset - size.height,
                      width: size.width, height: size.height)
    }

    /// Plays the poof centered on `point`, in its own short-lived overlay window.
    func showPoof(at point: CGPoint) {
        guard !HubFilesMotion.reduceMotion else { return }
        let side = HubFilesSidebarMetrics.poofSize
        let window = HubFilesOverlayWindow()
        window.show(HubFilesPoofView(), frame: CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side))
        Task {
            try? await Task.sleep(for: .seconds(HubFilesPoofView.duration + 0.1))
            window.hide()
        }
    }

    /// Flies each new folder's icon from `origin` (screen) to its row, then reveals the row.
    func launchFlights(for ids: [HubFilesSidebarEntryID], urls: [URL], from origin: CGPoint) {
        for (offset, pair) in zip(ids, urls).enumerated() {
            let (id, url) = pair
            guard let row = rowViews[id]?.view?.screenFrame else {
                flightLanded(on: id)
                continue
            }
            // Land on the row's glyph: 10 pt in, vertically centered.
            let end = CGPoint(x: row.minX + 10 + 9.5, y: row.midY)
            let delay = Double(offset) * 0.07
            let frame = CGRect(x: min(origin.x, end.x) - 60, y: min(origin.y, end.y) - 40,
                               width: abs(origin.x - end.x) + 120, height: abs(origin.y - end.y) + 180)
            // The view's coordinates are top-down from the window's top-left corner.
            let local = { (point: CGPoint) in CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y) }
            let window = HubFilesOverlayWindow()
            let icon = HubThumbnailCache.shared.icon(for: url)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                window.show(HubFilesFlightView(icon: icon, start: local(origin), end: local(end),
                                               duration: HubFilesSidebarMetrics.flightDuration),
                            frame: frame)
                try? await Task.sleep(for: .seconds(HubFilesSidebarMetrics.flightDuration))
                self?.flightLanded(on: id)
                // The icon fades over the glowing row before the window goes.
                try? await Task.sleep(for: .seconds(HubFilesFlightView.fadeDuration + 0.04))
                window.hide()
            }
        }
    }
}
