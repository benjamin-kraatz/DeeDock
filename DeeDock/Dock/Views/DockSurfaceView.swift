import SwiftUI

/// Composes app buttons, the pinned-section separator, and labels in a stable canvas.
///
/// Sizes and positions come from the same layout snapshot. App identity survives section moves,
/// and the existing spring applies to the whole surface rather than separate icon subtrees.
struct DockSurfaceView: View {
    let slots: [DockRenderSlot]
    private var items: [DockItem] { slots.compactMap(\.item) }
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
    let interaction: DockInteraction
    /// Reports actual button geometry, including during animation, for native click passthrough.
    let iconFrameChanged: (String, CGRect?) -> Void

    var menuTracking: (Bool) -> Void = { _ in }
    var accessibilityFocus: (String, Bool) -> Void = { _, _ in }

    private var opacity: DockAppearanceOpacity {
        DockAppearanceOpacity(settings: interaction.idleFade.settings,
            idleFraction: interaction.idleFade.fraction, reduceTransparency: reduceTransparency)
    }

    private var centers: [CGFloat] { layout.centers(sizes: sizes) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            DockBackgroundView(reduceTransparency: reduceTransparency,
                idleOpacity: opacity.background)
                .animation(interaction.idleFade.animation, value: opacity.background)
                .frame(width: surface.width, height: surface.height)
                .position(x: surface.midX, y: surface.midY)
            if slots.isEmpty {
                Text(.dockEmptyState)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(width: max(1, surface.width - 8), height: max(1, surface.height - 8))
                    .minimumScaleFactor(0.7)
                    .position(x: surface.midX, y: surface.midY)
            }
            if let index = layout.separatorIndex, index < centers.count {
                let icon = layout.iconFrame(centerAlong: centers[index], size: layout.iconSize)
                let position = centers[index] - sizes[index] / 2 - 12
                Rectangle().fill(.primary.opacity(0.18))
                    .animation(interaction.idleFade.animation) { $0.opacity(opacity.background) }
                    .frame(width: layout.edge.isVertical ? layout.iconSize * 0.65 : 1,
                           height: layout.edge.isVertical ? 1 : layout.iconSize * 0.65)
                    .position(x: layout.edge.isVertical ? icon.midX : position,
                              y: layout.edge.isVertical ? position : icon.midY + (layout.edge == .top ? -3 : 3))
                    .accessibilityHidden(true)
            }
            ForEach(Array(slots.enumerated()), id: \.element.id) {
                index,
                slot in
                if index < sizes.count {
                    let frame = layout.buttonFrame(
                        centerAlong: centers[index],
                        size: sizes[index]
                    )
                    let iconFrame = layout.iconFrame(
                        centerAlong: centers[index],
                        size: sizes[index]
                    )
                    if let item = slot.item {
                        DockAppButton(
                            item: item,
                            size: sizes[index],
                            isLaunching: launchingIDs.contains(item.id),
                            isSelected: keyboardFocus && selectedID == item.id,
                            open: { openApp(item) },
                            togglePin: { togglePin(item) },
                            interaction: interaction,
                            menuTracking: menuTracking,
                            accessibilityFocus: {
                                accessibilityFocus(item.id, $0)
                            }
                        )
                        .opacity(interaction.dragSourceID == item.id ? 0.3 : 1)
                        .onHover { inside in
                            if inside {
                                hoveredID = item.id
                            } else if hoveredID == item.id {
                                hoveredID = nil
                            }
                        }
                        .onGeometryChange(for: CGRect.self) {
                            $0.frame(in: .named("dockRoot"))
                        } action: {
                            iconFrameChanged(item.id, $0)
                        }
                        .onDisappear { iconFrameChanged(item.id, nil) }
                        .id(item.id)
                        .position(x: frame.midX, y: frame.midY)
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.accentColor.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10).strokeBorder(
                                    .tint,
                                    style: StrokeStyle(
                                        lineWidth: 1,
                                        dash: [3, 3]
                                    )
                                )
                            )
                            .frame(width: sizes[index], height: sizes[index])
                            .position(x: iconFrame.midX, y: iconFrame.midY)
                            .accessibilityHidden(true)
                            .allowsHitTesting(false)
                    }
                }
            }
            if let id = hoveredID ?? (keyboardFocus ? selectedID : nil),
                let index = slots.firstIndex(where: { $0.item?.id == id }),
                index < centers.count, showsLabel
            {
                let region = layout.calloutRegion(size: sizes[index], length: layout.canvasLength).intersection(viewport)
                DockHoverLabel(name: slots[index].item?.reference.name ?? "",
                    anchor: CGPoint(x: centers[index], y: layout.edge.isVertical ? centers[index] : (layout.edge == .top ? region.minY + 20 : region.maxY - 20)),
                    viewport: region, edge: layout.edge)
            }
        }
        .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.15),
            value: slots.map(\.id)
        )
        .animation(
            reduceMotion
                ? nil : .interpolatingSpring(stiffness: 300, damping: 30),
            value: sizes
        )
    }
}
