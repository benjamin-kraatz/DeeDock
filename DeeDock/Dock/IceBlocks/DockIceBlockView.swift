import SwiftUI

/// One slab of clear, lightly tinted glass with frosted faces and a lit rim.
///
/// The light sits on the side facing the screen edge, so the block reads as resting on that
/// edge whichever way the dock is oriented.
struct DockIceBlockView: View {
    let tint: Color
    /// Effective radius, capped by the caller to the block's bounds.
    let cornerRadius: CGFloat
    let edge: DockEdge
    let reduceTransparency: Bool
    /// A bar of light resting on the lit side, as on the reference's drives block.
    var lightBar = false
    /// Experiment: a captured picture of what is behind the dock. When present, the block
    /// redraws it through the refraction shader instead of using system glass.
    var backdrop: DockIceBackdrop.Frame? = nil

    @AppStorage(DockIceTuning.tintKey) private var tintPercent = DockIceTuning.tintDefault
    @AppStorage(DockIceTuning.shadeKey) private var shadePercent = DockIceTuning.shadeDefault
    @AppStorage(DockIceTuning.glowKey) private var glowPercent = DockIceTuning.glowDefault
    @AppStorage(DockIceTuning.frostKey) private var frostPercent = DockIceTuning.frostDefault
    @AppStorage(DockIceTuning.glassKey) private var glassMode = DockIceTuning.glassDefault
    @AppStorage(DockIceTuning.refractionStrengthKey) private var refraction = DockIceTuning.refractionStrengthDefault

    /// Width of the refracting rim in the edges-only glass mode.
    private static let glassEdge: CGFloat = 8
    /// Width of the rim the refraction shader bends, and its colour fringing.
    private static let refractionEdge: CGFloat = 14
    private static let refractionDispersion: CGFloat = 0.12
    /// Width of the lighter band that reads as the slab's side wall.
    private static let bevel: CGFloat = 4

    /// The side of the block that faces the screen edge.
    private var outward: UnitPoint {
        switch edge {
        case .bottom: .bottom
        case .top: .top
        case .left: .leading
        case .right: .trailing
        }
    }
    private var inward: UnitPoint { UnitPoint(x: 1 - outward.x, y: 1 - outward.y) }
    private var outwardAlignment: Alignment {
        switch edge {
        case .bottom: .bottom
        case .top: .top
        case .left: .leading
        case .right: .trailing
        }
    }
    private var inwardAlignment: Alignment {
        switch edge {
        case .bottom: .top
        case .top: .bottom
        case .left: .trailing
        case .right: .leading
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        let rim = tint.mix(with: .white, by: 0.55)
        if reduceTransparency {
            shape.fill(Color(nsColor: .windowBackgroundColor))
                .overlay(shape.fill(tint.opacity(0.18)))
                .overlay(shape.strokeBorder(tint.opacity(0.8), lineWidth: 1))
        } else {
            let glow = min(1, max(0, glowPercent / 100))
            let wash = min(0.6, max(0, tintPercent / 100))
            let frost = min(0.8, max(0, frostPercent / 100) * 1.75)
            // Even the clearest system glass blurs what is behind it, so clear ice keeps glass
            // out of the middle of the block: either a refracting ring along the rim, or none.
            Group {
                if let backdrop {
                    // The capture covers the panel's window frame, so this view's window
                    // coordinates are its position in the picture.
                    GeometryReader { proxy in
                        Rectangle().fill(.black)
                            .colorEffect(ShaderLibrary.dockIceRefraction(
                                .float2(proxy.size), .float(cornerRadius),
                                .float2(proxy.frame(in: .global).origin), .float(backdrop.scale),
                                .float(Self.refractionEdge), .float(refraction), .float(Self.refractionDispersion),
                                .image(Image(decorative: backdrop.image, scale: 1))))
                    }
                } else {
                switch DockIceGlassMode(rawValue: glassMode) ?? .edges {
                case .full:
                    shape.fill(.clear).glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
                case .edges:
                    shape.fill(.clear)
                        .glassEffect(.clear, in: shape.inset(by: Self.glassEdge / 2).stroke(lineWidth: Self.glassEdge))
                case .none:
                    shape.fill(.clear)
                }
                }
            }
                .overlay {
                    ZStack {
                        if shadePercent > 0 {
                            shape.fill(tint.mix(with: .black, by: 0.8).opacity(min(0.8, shadePercent / 100)))
                        }
                        // A thin colour wash that thickens toward the lit side.
                        shape.fill(LinearGradient(stops: [.init(color: tint.opacity(wash * 0.8), location: 0),
                                                          .init(color: tint.opacity(wash * 0.4), location: 0.45),
                                                          .init(color: tint.opacity(min(1, wash * 1.8)), location: 1)],
                                                  startPoint: inward, endPoint: outward))
                        // Light pooling inside the glass on the lit side. Normal blending, because
                        // additive light over a bright wallpaper floods the whole block.
                        shape.fill(EllipticalGradient(colors: [tint.opacity(0.45 * glow), tint.opacity(0)],
                                                      center: outward, startRadiusFraction: 0, endRadiusFraction: 0.55))
                        // A soft reflection across the desktop-side corner.
                        shape.fill(LinearGradient(colors: [.white.opacity(0.10), .white.opacity(0)],
                                                  startPoint: .topLeading, endPoint: .center))
                        // Frost: ice is clear in the middle and cloudy toward its faces.
                        if frost > 0 {
                            shape.stroke(rim.opacity(frost), lineWidth: 5).blur(radius: 6).clipShape(shape)
                        }
                        // The slab's side wall: a lighter band, closed by a faint inner edge
                        // that catches light on the desktop side.
                        shape.strokeBorder(rim.opacity(0.10), lineWidth: Self.bevel)
                        shape.inset(by: Self.bevel)
                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.03)],
                                                         startPoint: inward, endPoint: outward), lineWidth: 0.75)
                        // Coloured glow bleeding inward from the rim.
                        shape.stroke(tint.opacity(0.55 * glow), lineWidth: 4).blur(radius: 5).clipShape(shape)
                        shape.strokeBorder(LinearGradient(stops: [.init(color: rim.opacity(0.95), location: 0),
                                                                  .init(color: tint.opacity(0.55), location: 0.45),
                                                                  .init(color: rim, location: 1)],
                                                          startPoint: inward, endPoint: outward),
                                           lineWidth: 1.25)
                        // Specular lines on the two long sides: a white glint toward the desktop
                        // and a hot, glowing line where the block meets its own light.
                        edgeLine(.white.opacity(0.75), thickness: 1, spread: 0.5, glow: nil, alignment: inwardAlignment)
                        edgeLine(tint.mix(with: .white, by: 0.7), thickness: 1.5, spread: 0.3,
                                 glow: tint.opacity(glow), alignment: outwardAlignment)
                        if lightBar { bar }
                    }
                }
                .background { shape.stroke(tint.opacity(0.8 * glow), lineWidth: 3).blur(radius: 7) }
        }
    }

    /// A line along one long side that fades out before the corners begin. `spread` is where,
    /// from each end, the line reaches full strength.
    private func edgeLine(_ color: Color, thickness: CGFloat, spread: Double, glow: Color?,
                          alignment: Alignment) -> some View {
        let vertical = edge.isVertical
        return Capsule()
            .fill(LinearGradient(stops: [.init(color: color.opacity(0), location: 0),
                                         .init(color: color, location: spread),
                                         .init(color: color, location: 1 - spread),
                                         .init(color: color.opacity(0), location: 1)],
                                 startPoint: vertical ? .top : .leading, endPoint: vertical ? .bottom : .trailing))
            .frame(width: vertical ? thickness : nil, height: vertical ? nil : thickness)
            .shadow(color: glow ?? .clear, radius: glow == nil ? 0 : 5)
            .padding(vertical ? .vertical : .horizontal, cornerRadius * 0.8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    private var bar: some View {
        GeometryReader { proxy in
            let vertical = edge.isVertical
            let length = (vertical ? proxy.size.height : proxy.size.width) * 0.38
            Capsule()
                .fill(tint.mix(with: .white, by: 0.2))
                .frame(width: vertical ? 3 : length, height: vertical ? length : 3)
                .shadow(color: tint, radius: 5)
                .padding(3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: outwardAlignment)
        }
    }
}

#if DEBUG
#Preview("Ice blocks, every tint") {
    let roles: [DockIceBlockRole] = [.drives, .launcher, .pinned, .running, .utility]
    return VStack(spacing: 24) {
        HStack(spacing: 8) {
            ForEach(roles.indices, id: \.self) { index in
                DockIceBlockView(tint: roles[index].tint, cornerRadius: 22, edge: .bottom, reduceTransparency: false,
                                 lightBar: index == 0)
                    .frame(width: index == 1 ? 76 : 150, height: 76)
            }
        }
        HStack(spacing: 8) {
            ForEach(roles.indices, id: \.self) { index in
                DockIceBlockView(tint: roles[index].tint, cornerRadius: 22, edge: .bottom, reduceTransparency: true)
                    .frame(width: index == 1 ? 70 : 150, height: 70)
            }
        }
    }
    .padding(40)
    .background(.black)
    .preferredColorScheme(.dark)
}
#endif
