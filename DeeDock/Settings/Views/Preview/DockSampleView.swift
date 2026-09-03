import SwiftUI

/// Symbol tiles for Settings only. Uses production frames without resolving apps or owning native state.
struct DockSampleView: View {
    let layout: DockGeometry.Layout
    var magnified = false
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
        let pointer = magnified && layout.restingCenters.count > 2 ? layout.restingCenters[2] : nil
        let sizes = layout.sizes(pointerAlong: pointer, reduceMotion: reduceMotion)
        let centers = layout.centers(sizes: sizes)
        let glass = layout.surfaceFrame(sizes: sizes)
        ZStack(alignment: .topLeading) {
            DockBackgroundView(reduceTransparency: reduceTransparency, idleOpacity: opacity.background)
                .frame(width: glass.width, height: glass.height).position(x: glass.midX, y: glass.midY)
            ForEach(centers.indices, id: \.self) { index in
                let rect = layout.iconFrame(centerAlong: centers[index], size: sizes[index])
                RoundedRectangle(cornerRadius: sizes[index] * 0.23)
                    .fill(colors[index % colors.count].gradient)
                    .overlay {
                        Image(systemName: symbols[index % symbols.count])
                            .font(.system(size: sizes[index] * 0.44, weight: .medium)).foregroundStyle(.white)
                    }
                    .frame(width: rect.width, height: rect.height)
                    .opacity(opacity.icons)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .frame(width: layout.viewportSize.width, height: layout.viewportSize.height)
        .clipped().accessibilityHidden(true)
    }
}
