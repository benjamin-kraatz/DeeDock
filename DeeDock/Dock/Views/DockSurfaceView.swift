import SwiftUI

/// Composes app buttons, the pinned-section separator, and labels in a stable canvas.
///
/// Sizes and positions come from the same layout snapshot. App identity survives section moves,
/// and the existing spring applies to the whole surface rather than separate icon subtrees.
struct DockSurfaceView: View {
    let slots: [DockRenderSlot]
    let launchingIDs: Set<String>
    let selectedTarget: DockEntryID?
    let keyboardFocus: Bool
    let showsLabel: Bool
    let layout: DockGeometry.Layout
    let sizes: [CGFloat]
    let surface: CGRect
    /// Visible viewport expressed in the scrollable canvas coordinate space.
    let viewport: CGRect
    @Binding var hoveredID: DockEntryID?
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let primaryAppAction: (DockItem) -> Void
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
                cornerRadius: min(interaction.idleFade.settings.cornerRadius, min(surface.width, surface.height) / 2),
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
            ForEach(layout.separatorIndices.sorted(), id: \.self) { index in
                if index < centers.count {
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
                    DockEntryView(slot: slot, size: sizes[index],
                        launching: slot.item.map { launchingIDs.contains($0.id) } ?? false,
                        selected: keyboardFocus && selectedTarget == slot.target,
                        interaction: interaction, reduceTransparency: reduceTransparency,
                        primaryAppAction: primaryAppAction, openApp: openApp,
                        togglePin: togglePin, menuTracking: menuTracking,
                        accessibilityFocus: accessibilityFocus)
                        .onHover { inside in
                            if inside { hoveredID = slot.target }
                            else if hoveredID == slot.target { hoveredID = nil }
                        }
                        .onGeometryChange(for: DockEntryFrames.self) {
                            DockEntryFrames(root: $0.frame(in: .named("dockRoot")), canvas: $0.frame(in: .named("dockCanvas")))
                        } action: { frames in
                            guard let target = slot.target else { return }
                            iconFrameChanged(target.hitID, frames.root)
                            interaction.setRenderedFrame(frames.canvas, for: target)
                        }
                        .onDisappear {
                            guard let target = slot.target else { return }
                            iconFrameChanged(target.hitID, nil)
                            interaction.setRenderedFrame(nil, for: target)
                        }
                        .id(slot.id)
                        .position(x: slot.item == nil && slot.target == nil ? iconFrame.midX : frame.midX,
                                  y: slot.item == nil && slot.target == nil ? iconFrame.midY : frame.midY)
                }
            }
            DockTooltipsOverlay(slots: slots, frames: interaction.renderedFrames, hovered: hoveredID,
                selected: keyboardFocus ? selectedTarget : nil, enabled: showsLabel,
                layout: layout, viewport: viewport, interaction: interaction,
                reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
        }
        .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
        .coordinateSpace(name: "dockCanvas")
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.18),
            value: slots.map(\.id)
        )
        .animation(
            reduceMotion
                ? nil : .interpolatingSpring(stiffness: 300, damping: 30),
            value: sizes
        )
    }
}
