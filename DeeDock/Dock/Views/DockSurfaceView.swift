import SwiftUI

/// Composes app buttons, one glass island per section, and labels in a stable canvas.
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

    /// The launcher's glass stands in for the dock's while the two crossfade. Drawing both would
    /// stack two translucent materials, which reads as every surface brightening.
    var drawsBackground = true
    var menuTracking: (Bool) -> Void = { _ in }
    var accessibilityFocus: (String, Bool) -> Void = { _, _ in }

    private var opacity: DockAppearanceOpacity {
        DockAppearanceOpacity(
            settings: interaction.idleFade.settings,
            idleFraction: interaction.idleFade.fraction,
            reduceTransparency: reduceTransparency
        )
    }

    /// Inward-trailing corner of DDock glass, not an app pin.
    private var pipAlignment: Alignment {
        switch layout.edge {
        case .bottom: .topTrailing
        case .top: .bottomTrailing
        case .left: .trailing
        case .right: .leading
        }
    }

    var body: some View {
        // Computed once per pass. Each slot and island reads it, and this body runs on every
        // pointer move over the dock and every auto-hide frame.
        let centers = layout.centers(sizes: sizes)
        let islands = layout.islandFrames(sizes: sizes)
        ZStack(alignment: .topLeading) {
            if drawsBackground {
                let frames = islands.isEmpty ? [surface] : islands
                ForEach(Array(frames.enumerated()), id: \.offset) { index, frame in
                    let radius = min(interaction.idleFade.settings.cornerRadius, min(frame.width, frame.height) / 2)
                    let title = layout.islandTitles.indices.contains(index) ? layout.islandTitles[index] : nil
                    ZStack(alignment: .leading) {
                        DockBackgroundView(
                            reduceTransparency: reduceTransparency,
                            cornerRadius: radius,
                            idleOpacity: opacity.background
                        )
                        .animation(interaction.idleFade.animation, value: opacity.background)
                        .overlay {
                            if let breathing = interaction.focusBreathing {
                                FocusBreathingChrome(
                                    active: interaction.exposesContent && breathing.isActive(
                                        modeID: interaction.dockModes?.activeMode.id,
                                        sessionRunning: interaction.focusSession?.session?.phase == .running
                                    ),
                                    intensity: breathing.intensity,
                                    reduceMotion: reduceMotion,
                                    cornerRadius: radius,
                                    backgroundOpacity: opacity.background
                                )
                            }
                        }
                        .overlay(alignment: pipAlignment) {
                            #if DIRECT_DISTRIBUTION
                            if index == frames.count - 1, interaction.updateAwareness?.showsIndicators == true {
                                UpdateAwarenessPip(reduceMotion: reduceMotion)
                                    .padding(7)
                                    .allowsHitTesting(false)
                            }
                            #endif
                        }
                        .accessibilityHidden(true)
                        if let title {
                            // A point at the leading edge, so VoiceOver hears the section before its icons
                            // without a glass element covering those icons.
                            Color.clear
                                .frame(width: 1, height: 1)
                                .accessibilityLabel(Text(title))
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                }
            }
            if slots.isEmpty {
                Text(.dockEmptyState)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(
                        width: max(1, surface.width - 8),
                        height: max(1, surface.height - 8)
                    )
                    .minimumScaleFactor(0.7)
                    .position(x: surface.midX, y: surface.midY)
            }
            AppMeltDockBackgrounds(slots: slots, layout: layout, sizes: sizes,
                                   opacity: opacity.background, reduceTransparency: reduceTransparency)
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
                    DockEntryView(
                        slot: slot,
                        size: sizes[index],
                        launching: slot.item.map {
                            launchingIDs.contains($0.id)
                        } ?? false,
                        selected: keyboardFocus
                            && selectedTarget == slot.target,
                        interaction: interaction,
                        reduceTransparency: reduceTransparency,
                        primaryAppAction: primaryAppAction,
                        openApp: openApp,
                        togglePin: togglePin,
                        menuTracking: menuTracking,
                        accessibilityFocus: accessibilityFocus
                    )
                    .onHover { inside in
                        if inside {
                            hoveredID = slot.target
                        } else if hoveredID == slot.target {
                            hoveredID = nil
                        }
                    }
                    .onGeometryChange(for: DockEntryFrames.self) {
                        DockEntryFrames(
                            root: $0.frame(in: .named("dockRoot")),
                            canvas: $0.frame(in: .named("dockCanvas"))
                        )
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
                    .position(
                        x: slot.item == nil && slot.target == nil
                            ? iconFrame.midX : frame.midX,
                        y: slot.item == nil && slot.target == nil
                            ? iconFrame.midY : frame.midY
                    )
                }
            }
            // Canvas space, same as tooltips, so a scrolled pin still owns its burst.
            DockSoapBubbleOverlay(
                bursts: interaction.soapBubbles.bursts,
                frames: interaction.renderedFrames,
                enabled: interaction.soapBubbles.isEnabled
            )
            DockTooltipsOverlay(
                slots: slots,
                frames: interaction.renderedFrames,
                hovered: hoveredID,
                selected: keyboardFocus ? selectedTarget : nil,
                enabled: showsLabel,
                layout: layout,
                viewport: viewport,
                interaction: interaction,
                reduceMotion: reduceMotion,
                reduceTransparency: reduceTransparency
            )
        }
        .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
        .coordinateSpace(name: "dockCanvas")
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.18),
            value: slots.map(\.id)
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86),
            value: slots.compactMap { $0.melt?.id }
        )
        .animation(
            reduceMotion
                ? nil : .interpolatingSpring(stiffness: 300, damping: 30),
            value: sizes
        )
    }
}
