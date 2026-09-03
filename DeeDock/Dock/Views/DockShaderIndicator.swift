import SwiftUI

/// Procedural Metal artwork on one icon-sized rectangle, with a transparent center.
/// No timeline, textures, or layer sampling: uniforms change only when size or appearance changes.
struct DockShaderIndicator: View {
    let style: DockSettings.RunningIndicatorStyle
    let size: CGFloat
    let opaque: Bool

    private var shader: Shader? {
        let dimension = Shader.Argument.float(size)
        let solid = Shader.Argument.float(opaque ? 1.0 : 0.0)
        switch style {
        case .plasma: return ShaderLibrary.deeDockPlasma(dimension, solid)
        case .hologram: return ShaderLibrary.deeDockHologram(dimension, solid)
        case .solarFlare: return ShaderLibrary.deeDockSolarFlare(dimension, solid)
        case .prism: return ShaderLibrary.deeDockPrism(dimension, solid)
        default: return nil
        }
    }

    var body: some View {
        if let shader {
            Rectangle().fill(.white)
                .frame(width: size, height: size)
                .colorEffect(shader)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }
}

#if DEBUG
#Preview("Metal styles at small and large sizes") {
    VStack(spacing: 16) {
        ForEach([CGFloat(32), 64, 96], id: \.self) { size in
            HStack(spacing: 16) {
                ForEach([DockSettings.RunningIndicatorStyle.plasma, .hologram, .solarFlare, .prism], id: \.self) { style in
                    DockIconPresentation(icon: DockPreviewData.items[0].icon, size: size, edge: .bottom,
                        available: true, running: true, launching: false,
                        keyboardSelected: false, runningIndicatorStyle: style)
                }
            }
        }
    }.padding(20).preferredColorScheme(.dark)
}
#endif
