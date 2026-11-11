import SwiftUI

/// Everything the display's lamp lights on the orb: the top shine, the specular dot, the rim
/// light ring and the bottom caustic. They are drawn as if the lamp were straight above, then
/// the whole layer turns toward the lamp (``VaporLighting/angle``). Brightness follows
/// ``VaporLighting/intensity``, which falls off with distance from the lamp.
///
/// The angle changes only when the orb moves, so this costs one rotation at rest.
struct VaporOrbLitLayers: View {
    let lighting: VaporLighting
    let palette: VaporOrbPalette

    var body: some View {
        let lit = lighting.intensity
        GeometryReader { proxy in
            let side = proxy.size.width
            ZStack(alignment: .topLeading) {
                // Bottom caustic: light focused through the glass onto its far side.
                Ellipse()
                    .fill(EllipticalGradient(colors: [Color(red: 170 / 255, green: 220 / 255, blue: 1, opacity: 0.55), .clear],
                                             center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5))
                    .frame(width: side * 0.52, height: side * 0.2)
                    .blur(radius: 2)
                    .blendMode(.screen)
                    .opacity(0.5 + lit * 0.5)
                    .offset(x: side * 0.24, y: side * 0.75)
                VaporOrbRimLight(side: side)
                    .opacity(lit * 0.8)
                Ellipse()
                    .fill(LinearGradient(stops: [.init(color: palette.glint, location: 0),
                                                 .init(color: .white.opacity(0), location: 0.85)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: side * 0.7, height: side * 0.42)
                    .opacity(0.35 + lit * 0.6)
                    .offset(x: side * 0.15, y: side * 0.05)
                Ellipse()
                    .fill(.white)
                    .frame(width: side * 0.14, height: side * 0.08)
                    .blur(radius: 1.2)
                    .opacity(0.4 + lit * 0.55)
                    .offset(x: side * 0.43, y: side * 0.09)
            }
            .frame(width: side, height: side, alignment: .topLeading)
        }
        .rotationEffect(.radians(lighting.angle))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The thin lit ring just inside the glass's edge: bright at the top, clear at the sides, a
/// cool glow at the bottom.
private struct VaporOrbRimLight: View {
    let side: CGFloat

    var body: some View {
        Circle()
            .fill(LinearGradient(stops: [.init(color: .white.opacity(0.7), location: 0),
                                         .init(color: .white.opacity(0), location: 0.32),
                                         .init(color: .white.opacity(0), location: 0.78),
                                         .init(color: Color(red: 150 / 255, green: 210 / 255, blue: 1, opacity: 0.45), location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .mask {
                // Transparent inside 89 % of the radius, opaque at the edge.
                RadialGradient(stops: [.init(color: .clear, location: 0.89), .init(color: .black, location: 1)],
                               center: .center, startRadius: 0, endRadius: side / 2)
            }
            .frame(width: side, height: side)
    }
}

/// The soft contact shadow under the orb. It slides away from the lamp and stretches when the
/// lamp is off to one side. While the orb is dragged, the shadow drops and shrinks, so the orb
/// reads as lifted.
struct VaporOrbShadow: View {
    let lighting: VaporLighting
    let palette: VaporOrbPalette
    let isLifted: Bool

    var body: some View {
        let diameter = VaporGeometry.orbDiameter
        Ellipse()
            .fill(EllipticalGradient(colors: [palette.shadow, .clear], center: .center,
                                     startRadiusFraction: 0, endRadiusFraction: 0.5))
            .frame(width: diameter * 0.72, height: diameter * 0.15)
            .blur(radius: 3)
            .scaleEffect(x: lighting.shadowStretch * (isLifted ? 0.85 : 1), y: isLifted ? 0.85 : 1)
            .offset(x: lighting.shadowOffset.width, y: diameter * 0.595 + (isLifted ? 8 : 0))
            .opacity(isLifted ? 0.6 : 1)
            .animation(.easeOut(duration: 0.15), value: isLifted)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The soft white flash inside the glass when the orb evaporates its folders.
struct VaporOrbFlash: View {
    var body: some View {
        Circle()
            .fill(RadialGradient(stops: [.init(color: .white.opacity(0.95), location: 0),
                                         .init(color: Color(red: 160 / 255, green: 215 / 255, blue: 1, opacity: 0.4), location: 0.45),
                                         .init(color: .clear, location: 0.7)],
                                 center: .center, startRadius: 0, endRadius: VaporGeometry.orbDiameter * 0.71))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
