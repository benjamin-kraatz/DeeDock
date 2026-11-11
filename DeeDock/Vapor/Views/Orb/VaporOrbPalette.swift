import SwiftUI

/// The orb's colours for light or dark appearance, glass or Reduce Transparency. Values follow
/// the approved mockup (`docs/mockups/vapor-orb.html`).
struct VaporOrbPalette {
    let isDark: Bool
    let reduceTransparency: Bool

    init(colorScheme: ColorScheme, reduceTransparency: Bool) {
        isDark = colorScheme == .dark
        self.reduceTransparency = reduceTransparency
    }

    /// The glass tint, centred a little above the middle. Opaque under Reduce Transparency.
    var baseGradient: RadialGradient {
        let stops: [Gradient.Stop]
        switch (isDark, reduceTransparency) {
        case (true, false):
            stops = [.init(color: .white.opacity(0.07), location: 0),
                     .init(color: Color(red: 90 / 255, green: 150 / 255, blue: 230 / 255, opacity: 0.10), location: 0.55),
                     .init(color: Color(red: 20 / 255, green: 50 / 255, blue: 110 / 255, opacity: 0.30), location: 1)]
        case (false, false):
            stops = [.init(color: .white.opacity(0.35), location: 0),
                     .init(color: Color(red: 170 / 255, green: 205 / 255, blue: 250 / 255, opacity: 0.20), location: 0.55),
                     .init(color: Color(red: 90 / 255, green: 140 / 255, blue: 220 / 255, opacity: 0.28), location: 1)]
        case (true, true):
            stops = [.init(color: Color(red: 0x26 / 255, green: 0x32 / 255, blue: 0x4A / 255), location: 0),
                     .init(color: Color(red: 0x15 / 255, green: 0x20 / 255, blue: 0x37 / 255), location: 1)]
        case (false, true):
            stops = [.init(color: Color(red: 0xEE / 255, green: 0xF3 / 255, blue: 0xFB / 255), location: 0),
                     .init(color: Color(red: 0xCD / 255, green: 0xD9 / 255, blue: 0xEC / 255), location: 1)]
        }
        // CSS `radial-gradient(circle at 50% 30%)` reaches the farthest corner: 0.86 of the side.
        return RadialGradient(stops: stops, center: UnitPoint(x: 0.5, y: 0.3),
                              startRadius: 0, endRadius: VaporGeometry.orbDiameter * 0.86)
    }

    /// The top shine's colour.
    var glint: Color { .white.opacity(isDark ? 0.5 : 0.75) }
    /// The thin rim line.
    var rimLine: Color { .white.opacity(isDark ? 0.30 : 0.75) }
    /// The count badge's fill.
    var badgeFill: Color {
        isDark ? Color(red: 22 / 255, green: 23 / 255, blue: 30 / 255, opacity: 0.86) : .white.opacity(0.92)
    }
    /// The contact shadow's core colour.
    var shadow: Color {
        isDark ? .black.opacity(0.42) : Color(red: 30 / 255, green: 40 / 255, blue: 80 / 255, opacity: 0.28)
    }
    /// Steam particles.
    var steam: Color { isDark ? Color(red: 215 / 255, green: 238 / 255, blue: 1) : .white }
    /// Sparks from a folder taken out.
    static let spark = Color(red: 1, green: 235 / 255, blue: 200 / 255)
    /// The cool light inside the glass: bottom glow, caustic and drop glow.
    static let iceBlue = Color(red: 140 / 255, green: 205 / 255, blue: 1)
    static let dropBlue = Color(red: 80 / 255, green: 170 / 255, blue: 1)
    static let refusalRed = Color(red: 1, green: 110 / 255, blue: 100 / 255)
}
