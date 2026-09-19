import SwiftUI
import Observation

/// One scene follows the focused window; pixels never enter observable view state.
@MainActor @Observable
final class AtmosphereWindowLightScene {
    var colors = AtmosphereWindowLightPalette.dzwei
    var settings = AtmosphereWindowLightSettings()
    var reduceMotion = false
    var reduceTransparency = false
    var visible = false
    var intensity = 0.5
}

/// A hollow, click-through halo leaves the window's content entirely untouched.
struct AtmosphereWindowLightView: View {
    let scene: AtmosphereWindowLightScene
    static let margin: CGFloat = 64

    private var animated: Bool {
        scene.visible && !scene.reduceMotion && !scene.reduceTransparency
            && (scene.settings.glowing || (scene.settings.rotates && scene.colors.dropFirst().contains(where: { $0 != scene.colors.first })))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !animated)) { context in
            let time = animated ? context.date.timeIntervalSinceReferenceDate : 0
            let rotation = scene.settings.rotates && animated ? time.truncatingRemainder(dividingBy: 24) / 24 * 360 : 0
            let pulse = scene.settings.glowing && animated ? 0.86 + 0.14 * sin(time * .pi / 3) : 1
            GeometryReader { proxy in
                let size = CGSize(width: max(0, proxy.size.width - Self.margin * 2),
                                  height: max(0, proxy.size.height - Self.margin * 2))
                let colors = scene.colors.map(\.color)
                let gradient = AngularGradient(colors: colors + [colors.first ?? .clear], center: .center,
                                               angle: .degrees(rotation))
                RoundedRectangle(cornerRadius: 12)
                    .stroke(gradient, lineWidth: scene.reduceTransparency ? 2 : 32)
                    .frame(width: size.width, height: size.height)
                    .blur(radius: scene.reduceTransparency ? 0 : 18)
                    .opacity(scene.reduceTransparency ? 0.65 : (0.30 + scene.intensity * 0.40) * pulse)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    .mask {
                        // Even-odd fill punches out the exact content rectangle, including its corners.
                        Path { path in
                            path.addRect(CGRect(origin: .zero, size: proxy.size))
                            path.addRect(CGRect(x: Self.margin, y: Self.margin, width: size.width, height: size.height))
                        }.fill(style: FillStyle(eoFill: true))
                    }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("DZWEI halo") {
    AtmosphereWindowLightView(scene: AtmosphereWindowLightScene())
        .frame(width: 600, height: 400).background(.black.opacity(0.85))
}
