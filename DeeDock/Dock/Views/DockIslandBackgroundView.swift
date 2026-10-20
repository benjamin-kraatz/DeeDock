import SwiftUI

/// One island's glass: the ice-block material from the DEE-85 concept, a thinner frost, or a
/// solid slab, tinted with the island's colour.
///
/// The ice look layers, outside in: an ambient tinted glow, the dock's native glass with a light
/// tint, a vertical tint wash, a light leak and a lit "lamp" line on the outer screen edge, a
/// diagonal sheen, and a thick frosted rim. Every layer is clipped to the same rounded rect so
/// the island reads as one block. Reduce Transparency draws the flat slab regardless of style.
struct DockIslandBackgroundView: View, Animatable {
    let style: DockIslandStyle
    let color: DockIslandColor
    /// Multiplier on tint alphas.
    let tintStrength: Double
    /// Multiplier on the lamp and glow alphas.
    let glow: Double
    /// Which screen edge the dock sits on; the lamp sits on that side.
    let edge: DockEdge
    let reduceTransparency: Bool
    /// Whether the ice style draws the lamp line.
    var showsLamp = true
    /// Rim width in points, already capped to the island's size by the caller.
    var rimWidth: CGFloat = 4
    var cornerRadius: CGFloat = 22
    /// Idle dimming. At full visibility the glass carries no opacity wrapper.
    var idleOpacity: Double = 1
    var accessibilityName: String? = nil

    var animatableData: Double {
        get { idleOpacity }
        set { idleOpacity = newValue }
    }

    @Environment(\.colorScheme) private var colorScheme

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous) }

    var body: some View {
        Group {
            if idleOpacity >= 1 {
                material
            } else if idleOpacity > 0 {
                material.opacity(idleOpacity)
            } else {
                Color.clear
            }
        }
        .accessibilityHidden(accessibilityName == nil)
        .accessibilityLabel(Text(verbatim: accessibilityName ?? ""))
    }

    /// The tint at a given lightness and alpha, already scaled by `tintStrength`.
    private func tint(_ lightness: Double, _ alpha: Double) -> Color {
        color.color(brightness: lightness, opacity: min(1, alpha * tintStrength))
    }

    private var isDark: Bool { colorScheme == .dark }

    @ViewBuilder private var material: some View {
        if reduceTransparency || style == .flat {
            flat
        } else if style == .frost {
            frost
        } else {
            ice
        }
    }

    // MARK: Styles

    private var flat: some View {
        shape.fill(Color(nsColor: .windowBackgroundColor))
            .overlay(shape.fill(tint(isDark ? 0.55 : 0.75, isDark ? 0.22 : 0.18)))
            .overlay(shape.strokeBorder(.primary.opacity(0.14), lineWidth: 0.5))
    }

    private var frost: some View {
        shape.fill(.clear)
            .glassEffect(.regular.tint(tint(0.70, 0.10)), in: shape)
            .overlay(shape.fill(LinearGradient(colors: [tint(0.80, 0.08), tint(0.60, 0.04)], startPoint: .top, endPoint: .bottom)))
            .overlay(shape.strokeBorder(.white.opacity(isDark ? 0.22 : 0.45), lineWidth: 0.5))
            .shadow(color: tint(0.65, 0.20 * glow), radius: 12)
    }

    private var ice: some View {
        shape.fill(.clear)
            // The native material carries the blur and refraction; the tint on it stays light so
            // the icons keep their own colour.
            .glassEffect(.regular.tint(tint(0.60, 0.12)), in: shape)
            .overlay(wash)
            .overlay(leak)
            .overlay(sheen)
            .overlay(rim)
            .overlay { if showsLamp { lamp } }
            .clipShape(shape)
            .shadow(color: tint(0.65, 0.32 * glow), radius: 14)
            .shadow(color: .black.opacity(isDark ? 0.40 : 0.18), radius: 16, y: 8)
    }

    // MARK: Ice layers

    /// Lighter at the inward edge, darker in the middle, tinted again toward the lamp.
    private var wash: some View {
        shape.fill(LinearGradient(
            stops: [.init(color: tint(0.85, 0.16), location: 0),
                    .init(color: tint(0.50, 0.07), location: 0.55),
                    .init(color: tint(0.70, 0.22), location: 1)],
            startPoint: inwardPoint, endPoint: outwardPoint))
    }

    /// Light spilling in from the lamp along the outer edge.
    private var leak: some View {
        shape.fill(RadialGradient(
            colors: [tint(0.78, 0.72 * glow), tint(0.78, 0)],
            center: outwardCenter, startRadius: 0, endRadius: leakRadius))
            .blur(radius: 6)
    }

    /// A diagonal highlight, as light catching a thick glass face.
    private var sheen: some View {
        shape.fill(LinearGradient(
            stops: [.init(color: .white.opacity(0.20), location: 0),
                    .init(color: .white.opacity(0.05), location: 0.22),
                    .init(color: .white.opacity(0), location: 0.42),
                    .init(color: .white.opacity(0), location: 0.70),
                    .init(color: .white.opacity(0.06), location: 1)],
            startPoint: .topLeading, endPoint: .bottomTrailing))
            .blendMode(.screen)
    }

    /// The frosted rim: brightest at the inward edge, tinted at the lamp side.
    private var rim: some View {
        shape.strokeBorder(LinearGradient(
            stops: [.init(color: .white.opacity(isDark ? 0.50 : 0.85), location: 0),
                    .init(color: .white.opacity(0.14), location: 0.30),
                    .init(color: tint(0.80, 0.14), location: 0.65),
                    .init(color: tint(0.85, 0.60), location: 1)],
            startPoint: inwardPoint, endPoint: outwardPoint), lineWidth: rimWidth)
            .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
    }

    /// A thin lit line just inside the rim on the screen-edge side, with a soft halo.
    private var lamp: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let inset = rimWidth + 1
            let along = edge.isVertical ? size.height : size.width
            let length = max(4, along * 0.80)
            Capsule()
                .fill(tint(0.90, 0.85 * glow))
                .frame(width: edge.isVertical ? 2 : length, height: edge.isVertical ? length : 2)
                .shadow(color: tint(0.80, 0.90 * glow), radius: 4)
                .shadow(color: tint(0.75, 0.60 * glow), radius: 12)
                .position(lampPosition(in: size, inset: inset))
        }
    }

    // MARK: Edge geometry

    /// Gradient start at the dock's inward side (toward the desktop).
    private var inwardPoint: UnitPoint {
        switch edge {
        case .bottom: .top
        case .top: .bottom
        case .left: .trailing
        case .right: .leading
        }
    }

    /// Gradient end at the screen edge.
    private var outwardPoint: UnitPoint {
        switch edge {
        case .bottom: .bottom
        case .top: .top
        case .left: .leading
        case .right: .trailing
        }
    }

    private var outwardCenter: UnitPoint {
        switch edge {
        case .bottom: UnitPoint(x: 0.5, y: 1.08)
        case .top: UnitPoint(x: 0.5, y: -0.08)
        case .left: UnitPoint(x: -0.08, y: 0.5)
        case .right: UnitPoint(x: 1.08, y: 0.5)
        }
    }

    private var leakRadius: CGFloat { 120 }

    private func lampPosition(in size: CGSize, inset: CGFloat) -> CGPoint {
        switch edge {
        case .bottom: CGPoint(x: size.width / 2, y: size.height - inset)
        case .top: CGPoint(x: size.width / 2, y: inset)
        case .left: CGPoint(x: inset, y: size.height / 2)
        case .right: CGPoint(x: size.width - inset, y: size.height / 2)
        }
    }
}

#if DEBUG
    #Preview("Ice, frost, and flat") {
        let colors = [DockIslandPalette.color(for: .tile), DockIslandPalette.color(for: .pinned),
                      DockIslandPalette.color(for: .running), DockIslandPalette.color(for: .utilities)]
        VStack(spacing: 24) {
            ForEach(DockIslandStyle.allCases, id: \.self) { style in
                HStack(spacing: 16) {
                    ForEach(colors, id: \.self) { color in
                        DockIslandBackgroundView(style: style, color: color, tintStrength: 1, glow: 1, edge: .bottom,
                                                 reduceTransparency: false)
                            .frame(width: 140, height: 68)
                    }
                }
            }
            HStack(spacing: 16) {
                DockIslandBackgroundView(style: .ice, color: colors[0], tintStrength: 1, glow: 1, edge: .left,
                                         reduceTransparency: false)
                    .frame(width: 68, height: 160)
                DockIslandBackgroundView(style: .ice, color: colors[1], tintStrength: 1, glow: 1, edge: .top,
                                         reduceTransparency: false)
                    .frame(width: 200, height: 68)
                DockIslandBackgroundView(style: .ice, color: colors[2], tintStrength: 1, glow: 1, edge: .bottom,
                                         reduceTransparency: true)
                    .frame(width: 200, height: 68)
            }
        }
        .padding(40)
        .background(LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.12), Color(red: 0.16, green: 0.12, blue: 0.30)],
                                   startPoint: .top, endPoint: .bottom))
        .preferredColorScheme(.dark)
    }
#endif
