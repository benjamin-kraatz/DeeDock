import SwiftUI

struct AtmosphereAmbientView: View {
    let scene: AtmosphereScene
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if scene.reduceTransparency {
                    Canvas { context, size in
                        var rim = Path()
                        rim.move(to: .zero); rim.addLine(to: CGPoint(x: size.width, y: 0))
                        rim.move(to: CGPoint(x: 0, y: size.height)); rim.addLine(to: CGPoint(x: size.width, y: size.height))
                        if scene.leftEdge { rim.move(to: .zero); rim.addLine(to: CGPoint(x: 0, y: size.height)) }
                        if scene.rightEdge { rim.move(to: CGPoint(x: size.width, y: 0)); rim.addLine(to: CGPoint(x: size.width, y: size.height)) }
                        context.stroke(rim, with: .color(scene.palette.first.color), lineWidth: AtmosphereLimits.rimWidth(intensity: scene.settings.intensity))
                    }
                } else {
                    let width = max(proxy.size.width, scene.canvasWidth)
                    LinearGradient(colors: [scene.palette.first.color, scene.palette.second.color], startPoint: .leading, endPoint: .trailing)
                        .frame(width: width)
                        .mask {
                            ZStack {
                                LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .clear, location: 0.16), .init(color: .clear, location: 0.84), .init(color: .white, location: 1)], startPoint: .top, endPoint: .bottom)
                                HStack(spacing: 0) {
                                    LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 120)
                                    Spacer(minLength: 0)
                                    LinearGradient(colors: [.clear, .white], startPoint: .leading, endPoint: .trailing).frame(width: 120)
                                }
                            }
                        }
                        .offset(x: -scene.offset)
                        .opacity(AtmosphereLimits.ambientOpacity(preset: scene.settings.preset, intensity: scene.settings.intensity))
                }
                if scene.settings.preset.hasDecor && scene.settings.density > 0 {
                    if scene.reduceMotion || scene.reduceTransparency || scene.paused {
                        particles(time: 0, size: proxy.size)
                    } else {
                        TimelineView(.animation(minimumInterval: 1 / 20)) { timeline in
                            particles(time: timeline.date.timeIntervalSinceReferenceDate, size: proxy.size)
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .opacity(scene.paused ? 0.15 : 1)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func particles(time: Double, size: CGSize) -> some View {
        Canvas { context, _ in
            let count = Int(scene.settings.density * (scene.settings.preset == .party ? 64 : 22))
            for index in 0..<count {
                let seed = Double(index)
                let progress = (seed * 0.618 + time / (scene.settings.preset == .party ? 18 : 40)).truncatingRemainder(dividingBy: 1)
                let left = index.isMultiple(of: 2)
                guard left ? scene.leftEdge : scene.rightEdge else { continue }
                let x = left ? 8 + seed.truncatingRemainder(dividingBy: 5) * 10 : size.width - 8 - seed.truncatingRemainder(dividingBy: 5) * 10
                let point = CGPoint(x: x, y: size.height * (1 - progress))
                let symbol = scene.settings.preset == .party ? "sparkle" : "heart.fill"
                context.draw(Image(systemName: symbol), at: point)
            }
        }
        .foregroundStyle(scene.palette.second.color.opacity(0.5))
    }
}

#if DEBUG
#Preview("Atmosphere, static presets") {
    Grid {
        ForEach(AtmospherePreset.allCases, id: \.self) { preset in
            let scene = {
                let scene = AtmosphereScene()
                scene.settings.preset = preset
                scene.reduceMotion = true
                scene.canvasWidth = 500
                return scene
            }()
            GridRow {
                Text(preset.title)
                ZStack(alignment: .bottomLeading) {
                    Color.black
                    AtmosphereAmbientView(scene: scene)
                    if preset.hasDecor { AtmosphereDecorView(scene: scene) }
                }.frame(width: 500, height: 180)
            }
        }
    }.padding()
}

#Preview("Atmosphere intensity") {
    HStack(spacing: 12) {
        ForEach([0.0, AtmosphereLimits.defaultIntensity, 1.0], id: \.self) { intensity in
            let scene = {
                let scene = AtmosphereScene()
                scene.settings.intensity = intensity
                scene.reduceMotion = true
                scene.canvasWidth = 220
                return scene
            }()
            ZStack {
                Color.black
                AtmosphereAmbientView(scene: scene)
            }
            .frame(width: 220, height: 140)
        }
    }.padding()
}
#endif
