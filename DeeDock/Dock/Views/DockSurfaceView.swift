import SwiftUI

/// Composes app buttons, the pinned-section separator, and labels in a stable canvas.
///
/// Sizes and positions come from the same layout snapshot. App identity survives section moves,
/// and the existing spring applies to the whole surface rather than separate icon subtrees.
struct DockSurfaceView: View {
    let items: [DockItem]
    let launchingIDs: Set<String>
    let selectedID: String?
    let keyboardFocus: Bool
    let showsLabel: Bool
    let layout: DockGeometry.Layout
    let sizes: [CGFloat]
    let surface: CGRect
    /// Visible viewport expressed in the scrollable canvas coordinate space.
    let viewport: CGRect
    @Binding var hoveredID: String?
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let openApp: (DockItem) -> Void
    let togglePin: (DockItem) -> Void
    /// Reports actual button geometry, including during animation, for native click passthrough.
    let iconFrameChanged: (String, CGRect?) -> Void

    var menuTracking: (Bool) -> Void = { _ in }
    var accessibilityFocus: (String, Bool) -> Void = { _, _ in }

    private var centers: [CGFloat] { layout.centers(sizes: sizes) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            DockBackgroundView(reduceTransparency: reduceTransparency)
                .frame(width: surface.width, height: surface.height)
                .position(x: surface.midX, y: surface.midY)
            if items.isEmpty {
                Text(.dockEmptyState)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(width: layout.canvasWidth)
                    .position(x: layout.canvasWidth / 2, y: surface.midY)
            }
            if let index = layout.separatorIndex, index < centers.count {
                Rectangle().fill(.primary.opacity(0.18))
                    .frame(width: 1, height: layout.iconSize * 0.65)
                    .position(x: centers[index] - sizes[index] / 2 - 12,
                              y: layout.panelHeight - DockGeometry.bottomMargin - 36)
                    .accessibilityHidden(true)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index < sizes.count {
                    let frame = layout.buttonFrame(centerX: centers[index], size: sizes[index])
                    DockAppButton(item: item, size: sizes[index], isLaunching: launchingIDs.contains(item.id),
                                  isSelected: keyboardFocus && selectedID == item.id,
                                  open: { openApp(item) }, togglePin: { togglePin(item) },
                                  menuTracking: menuTracking, accessibilityFocus: { accessibilityFocus(item.id, $0) })
                        .onHover { inside in
                            if inside { hoveredID = item.id }
                            else if hoveredID == item.id { hoveredID = nil }
                        }
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("dockRoot")) } action: {
                            iconFrameChanged(item.id, $0)
                        }
                        .onDisappear { iconFrameChanged(item.id, nil) }
                        .id(item.id)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
            if let id = hoveredID ?? (keyboardFocus ? selectedID : nil),
               let index = items.firstIndex(where: { $0.id == id }), index < centers.count, showsLabel {
                DockHoverLabel(name: items[index].reference.name,
                               anchor: CGPoint(x: centers[index], y: min(surface.minY,
                                   layout.buttonFrame(centerX: centers[index], size: sizes[index]).minY - 12) - 20),
                               viewport: viewport)
            }
        }
        .frame(width: layout.canvasWidth, height: layout.panelHeight)
        .animation(reduceMotion ? nil : .interpolatingSpring(stiffness: 300, damping: 30), value: sizes)
    }
}
