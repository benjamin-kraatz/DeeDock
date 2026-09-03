import SwiftUI

/// Symbol tiles for Settings only. Uses production frames without resolving apps or owning native state.
struct DockSampleView: View {
    let layout: DockGeometry.Layout
    var magnified = false
    /// Explicit pointer position along the dock, for animated demonstrations such as the
    /// first-launch tour. Takes precedence over `magnified`, which picks a fixed icon.
    var pointerAlong: CGFloat? = nil
    var runningIndicatorStyle: DockSettings.RunningIndicatorStyle = .dot
    var appearanceSettings = DockSettings.defaults
    var idleFraction: Double = 0
    var reduceMotionOverride: Bool? = nil
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    var reduceTransparencyOverride: Bool? = nil
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    private var reduceTransparency: Bool { reduceTransparencyOverride ?? systemReduceTransparency }
    private let symbols = ["safari", "envelope.fill", "music.note", "camera.fill", "terminal.fill", "gearshape.fill"]
    private let colors: [Color] = [.blue, .cyan, .pink, .orange, .gray, .indigo]

    var body: some View {
        let opacity = DockAppearanceOpacity(settings: appearanceSettings, idleFraction: idleFraction, reduceTransparency: reduceTransparency)
        let pointer = pointerAlong ?? (magnified && layout.restingCenters.count > 2 ? layout.restingCenters[2] : nil)
        let sizes = layout.sizes(pointerAlong: pointer, reduceMotion: reduceMotion)
        let centers = layout.centers(sizes: sizes)
        let glass = layout.surfaceFrame(sizes: sizes)
        ZStack(alignment: .topLeading) {
            DockBackgroundView(reduceTransparency: reduceTransparency, idleOpacity: opacity.background)
                .frame(width: glass.width, height: glass.height).position(x: glass.midX, y: glass.midY)
            ForEach(centers.indices, id: \.self) { index in
                let rect = layout.iconFrame(centerAlong: centers[index], size: sizes[index])
                RoundedRectangle(cornerRadius: sizes[index] * 0.2)
                    .fill(colors[index % colors.count].gradient)
                    .overlay {
                        Image(systemName: symbols[index % symbols.count])
                            .font(.system(size: sizes[index] * 0.4, weight: .medium)).foregroundStyle(.white)
                    }
                    // Application artwork carries its own transparent margin. Samples need one
                    // drawn, or the shader styles have nowhere to put their light.
                    .padding(sizes[index] * 0.08)
                    .frame(width: rect.width, height: rect.height)
                    .modifier(DockIconIndicator(style: runningIndicatorStyle,
                                                running: index.isMultiple(of: 2), size: sizes[index],
                                                variant: DockIndicatorVariant(identity: symbols[index % symbols.count],
                                                                              accent: colors[index % colors.count]),
                                                animated: appearanceSettings.animateIndicators && !reduceMotion,
                                                reduceTransparency: reduceTransparencyOverride))
                    .opacity(opacity.icons)
                    .position(x: rect.midX, y: rect.midY)
                if index.isMultiple(of: 2) {
                    let button = layout.buttonFrame(centerAlong: centers[index], size: sizes[index])
                    let depth = sizes[index] + DockGeometry.indicatorAreaDepth
                    let marker = layout.edge.point(CGPoint(x: sizes[index] / 2,
                        y: sizes[index] + DockGeometry.indicatorSpacing + DockGeometry.indicatorSize / 2), depth: depth)
                    DockRunningIndicator(style: runningIndicatorStyle, edge: layout.edge)
                        .opacity(opacity.icons)
                        .position(x: button.minX + marker.x, y: button.minY + marker.y)
                }
            }
        }
        .frame(width: layout.viewportSize.width, height: layout.viewportSize.height)
        .clipped().accessibilityHidden(true)
    }
}
