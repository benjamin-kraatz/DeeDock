import SwiftUI

/// Flix Files' measurements and colours, from the approved mockup (`docs/mockups/flix-files-ai.html`).
///
/// Colours are semantic (they follow light and dark appearance) except the intelligence gradient,
/// which is the mockup's own. Metrics are in points.
enum FlixStyle {
    static let cornerRadius: CGFloat = 16
    static let sidebarWidth: CGFloat = 184
    static let headerHeight: CGFloat = 46
    static let footerHeight: CGFloat = 28
    static let rowHeight: CGFloat = 50
    static let childRowHeight: CGFloat = 44
    static let rowRadius: CGFloat = 9
    static let iconSize: CGFloat = 36

    /// The ✦ gradient: violet, blue, pink.
    static let aiGradient = LinearGradient(colors: [Color(red: 0.545, green: 0.424, blue: 1),
                                                    Color(red: 0.227, green: 0.659, blue: 1),
                                                    Color(red: 1, green: 0.435, blue: 0.694)],
                                           startPoint: .leading, endPoint: .trailing)
    /// The two-stop gradient behind primary ✦ buttons and the tile pill.
    static let aiButtonGradient = LinearGradient(colors: [Color(red: 0.545, green: 0.424, blue: 1),
                                                          Color(red: 0.227, green: 0.659, blue: 1)],
                                                 startPoint: .leading, endPoint: .trailing)
    static let aiViolet = Color(red: 0.545, green: 0.424, blue: 1)
    static let aiSoft = Color(red: 0.588, green: 0.431, blue: 1).opacity(0.16)
    static let aiStroke = Color(red: 0.545, green: 0.424, blue: 1).opacity(0.35)

    static let chip = Color.primary.opacity(0.07)
    static let chipHover = Color.primary.opacity(0.12)
    static let hover = Color.primary.opacity(0.06)
    static let line = Color.primary.opacity(0.08)
    static let pane = Color.primary.opacity(0.035)

    /// The spring rows use when they move.
    static let rowSpring = Animation.spring(response: 0.36, dampingFraction: 0.86)
}

/// A "✦" drawn in the intelligence gradient. Decorative; VoiceOver skips it.
struct FlixSparkle: View {
    var size: CGFloat = 12

    var body: some View {
        Text(verbatim: "✦")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(FlixStyle.aiGradient)
            .accessibilityHidden(true)
    }
}

/// The panel's background: glass-like material, or solid with Reduce Transparency.
struct FlixPanelBackground: View {
    let reduceTransparency: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FlixStyle.cornerRadius, style: .continuous)
        Group {
            if reduceTransparency {
                shape.fill(Color(nsColor: .windowBackgroundColor))
            } else {
                shape.fill(.regularMaterial)
            }
        }
        .overlay(shape.strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 28, y: 14)
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
    }
}
