import SwiftUI

/// Resolves hover/keyboard requests and places one shared tooltip in the reserved inward band.
struct DockTooltipsOverlay: View {
    let slots: [DockRenderSlot]
    let frames: [DockEntryID: CGRect]
    let hovered: DockEntryID?
    let selected: DockEntryID?
    let enabled: Bool
    let layout: DockGeometry.Layout
    let viewport: CGRect
    let interaction: DockInteraction
    let reduceMotion: Bool
    let reduceTransparency: Bool
    @State private var measuredSize = CGSize(width: 180, height: 30)

    private var request: DockTooltipController.Request {
        let candidate = hovered ?? selected
        // The open DOKK Hub points at its tile, so the tile's name would only cover the pointer.
        let valid = slots.contains { $0.target != nil && $0.target == candidate }
            && !(candidate == .launcher && interaction.hubTile?.isOpen == true)
        return .init(target: enabled && !interaction.suppressTooltips && valid ? candidate : nil,
              preset: interaction.tooltipPreset, keyboard: hovered == nil && selected != nil, reduceMotion: reduceMotion)
    }

    var body: some View {
        ZStack {
            if enabled, !interaction.suppressTooltips, let target = interaction.tooltips.visible,
               let slot = slots.first(where: { $0.target == target }), let iconFrame = frames[target] {
                let size = interaction.tooltipPreset.placement == .dockCenter
                    ? layout.iconSize * layout.magnification : layout.edge.length(of: iconFrame.size)
                let region = layout.calloutRegion(size: size, length: layout.canvasLength).intersection(viewport)
                let dock = layout.surfaceFrame(sizes: Array(repeating: layout.iconSize, count: slots.count)).intersection(viewport)
                let frame = DockTooltipGeometry.frame(size: measuredSize, icon: iconFrame, dock: dock, region: region,
                                                      edge: layout.edge, placement: interaction.tooltipPreset.placement)
                let artwork = DockTooltipArtwork(name: slot.name, icon: slot.icon, preset: interaction.tooltipPreset,
                    edge: layout.edge, maximumWidth: max(1, region.width - 16), reduceTransparency: reduceTransparency,
                    badge: DockTooltipBadge(slot: slot, interaction: interaction))
                artwork
                    .onGeometryChange(for: CGSize.self) { $0.size } action: {
                        if measuredSize != $0 { measuredSize = $0 }
                    }
                    // Root space, like the icon hit rects, so the panel converts it to the screen the
                    // same way it anchors Window Peek.
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("dockRoot")) } action: { rect in
                        interaction.tooltips.presented = .init(target: target, frame: rect, artwork: artwork)
                    }
                    // Follow already-rendered icon geometry without applying a second hover spring.
                    .animation(nil) { content in
                        content.frame(width: frame.width, height: frame.height).clipped()
                            .position(x: frame.midX, y: frame.midY)
                    }
                    .id(target)
                    .transition(interaction.tooltipPreset.transition(edge: layout.edge, reduceMotion: reduceMotion))
            }
        }
        .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
        .allowsHitTesting(false).accessibilityHidden(true)
        .animation(interaction.tooltipPreset.animation(reduceMotion: reduceMotion), value: interaction.tooltips.visible)
        .onChange(of: request, initial: true) { _, value in interaction.tooltips.update(value) }
        .onChange(of: interaction.tooltips.revision) { _, _ in interaction.tooltips.update(request) }
        .onChange(of: interaction.tooltips.visible) { _, target in
            guard let target, let slot = slots.first(where: { $0.target == target }),
                  let badge = DockTooltipBadge(slot: slot, interaction: interaction), badge.summary != nil else { return }
            Analytics.count(.badgeDetailShown(banner: badge.banner != nil))
        }
        .onDisappear { interaction.tooltips.clear() }
    }
}
