import SwiftUI

/// The panel's surface: native Liquid Glass tinted with the window background colour, as the Hub
/// draws its glass, with the mockup's hairline rim and soft shadow.
///
/// The tint keeps rows readable over any wallpaper; Increase Contrast strengthens it and the rim.
/// Reduce Transparency raises the tint to a solid fill and sets the glass to `.identity`. Both
/// cases keep one view structure, so switching the option with the panel open never rebuilds the
/// content (which would drop focus and scroll position).
struct FlixPanelGlass: ViewModifier {
    let reduceTransparency: Bool
    let increaseContrast: Bool

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: FlixStyle.cornerRadius, style: .continuous)
        content
            .background { shape.fill(FlixStyle.surface.opacity(fillOpacity)) }
            .clipShape(shape)
            .glassEffect(reduceTransparency ? .identity : .regular, in: shape)
            .overlay {
                shape.strokeBorder(Color.primary.opacity(increaseContrast ? 0.5 : colorScheme == .dark ? 0.15 : 0.12),
                                   lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .background { FlixPanelShadow(shape: shape) }
    }

    private var fillOpacity: Double {
        if reduceTransparency { return 1 }
        return HubStyle.glassTintOpacity(dark: colorScheme == .dark, increaseContrast: increaseContrast)
    }
}

/// The panel's shadow, drawn only outside its outline so it never darkens the glass from behind.
private struct FlixPanelShadow: View {
    let shape: RoundedRectangle

    var body: some View {
        shape.fill(.black)
            .shadow(color: .black.opacity(0.3), radius: 22, y: 10)
            .shadow(color: .black.opacity(0.14), radius: 5, y: 2)
            .mask {
                // Everything but the panel's own outline. The margin matches the window's.
                Rectangle()
                    .padding(-FlixPanelGeometry.shadowMargin)
                    .overlay { shape.blendMode(.destinationOut) }
                    .compositingGroup()
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// An opaque floating surface over the list: sheets and the drop question. Opaque by design, so it
/// reads the same over glass and needs no Reduce Transparency variant.
struct FlixFloatingSurface: ViewModifier {
    var radius: CGFloat = FlixStyle.surfaceRadius

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(FlixStyle.surface, in: shape)
            .overlay(shape.strokeBorder(FlixStyle.outline, lineWidth: 0.5).allowsHitTesting(false))
            .shadow(color: .black.opacity(0.28), radius: 20, y: 10)
            .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
    }
}
