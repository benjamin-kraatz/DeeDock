import SwiftUI

/// Shared measurements for the System Settings Clone window.
enum SystemSettingsCloneMetrics {
    static let sidebarWidth: CGFloat = 252
    /// Room above the sidebar list for the window's traffic lights.
    static let titlebarClearance: CGFloat = 40
    static let contentMaxWidth: CGFloat = 860
    static let sectionRadius: CGFloat = 20
    static let tileRadius: CGFloat = 12
    static let tileMinimumWidth: CGFloat = 228
}

/// Icon colors, modeled on the hues System Settings uses so destinations stay recognizable.
enum SystemSettingsCloneTint: String, Sendable {
    case blue, cyan, teal, green, yellow, orange, red, pink, purple, indigo, iris, gray, graphite

    /// Top-to-bottom gradient stops. The lower stop keeps contrast for a white symbol.
    var colors: [Color] {
        switch self {
        case .blue: [Color(red: 0.26, green: 0.60, blue: 1.00), Color(red: 0.04, green: 0.40, blue: 0.93)]
        case .cyan: [Color(red: 0.36, green: 0.80, blue: 0.98), Color(red: 0.07, green: 0.56, blue: 0.86)]
        case .teal: [Color(red: 0.30, green: 0.80, blue: 0.78), Color(red: 0.05, green: 0.56, blue: 0.60)]
        case .green: [Color(red: 0.38, green: 0.86, blue: 0.46), Color(red: 0.12, green: 0.64, blue: 0.28)]
        case .yellow: [Color(red: 1.00, green: 0.82, blue: 0.24), Color(red: 0.95, green: 0.60, blue: 0.04)]
        case .orange: [Color(red: 1.00, green: 0.64, blue: 0.24), Color(red: 0.95, green: 0.42, blue: 0.06)]
        case .red: [Color(red: 1.00, green: 0.42, blue: 0.40), Color(red: 0.90, green: 0.16, blue: 0.20)]
        case .pink: [Color(red: 1.00, green: 0.42, blue: 0.56), Color(red: 0.90, green: 0.16, blue: 0.36)]
        case .purple: [Color(red: 0.76, green: 0.46, blue: 0.96), Color(red: 0.54, green: 0.22, blue: 0.84)]
        case .indigo: [Color(red: 0.46, green: 0.44, blue: 0.98), Color(red: 0.30, green: 0.24, blue: 0.84)]
        case .iris: [Color(red: 0.98, green: 0.46, blue: 0.62), Color(red: 0.40, green: 0.34, blue: 0.98)]
        case .gray: [Color(red: 0.62, green: 0.63, blue: 0.67), Color(red: 0.44, green: 0.45, blue: 0.50)]
        case .graphite: [Color(red: 0.36, green: 0.37, blue: 0.40), Color(red: 0.14, green: 0.15, blue: 0.17)]
        }
    }

    /// Single color for glows, highlights, and selection washes.
    var accent: Color {
        switch self {
        case .gray, .graphite: Color(red: 0.52, green: 0.54, blue: 0.60)
        default: colors[1]
        }
    }
}

/// Rounded, softly lit symbol artwork in the style of System Settings icons.
struct SystemSettingsCloneIconTile: View {
    let symbolName: String
    let tint: SystemSettingsCloneTint
    var size: CGFloat = 28

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
    }

    var body: some View {
        shape
            .fill(LinearGradient(colors: tint.colors, startPoint: .top, endPoint: .bottom))
            .overlay {
                // Top sheen gives the tile depth without a heavy bevel.
                shape.fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center))
            }
            .overlay {
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.18), radius: 0.6, y: 0.6)
            }
            .overlay {
                shape.strokeBorder(.white.opacity(0.16), lineWidth: 0.75)
            }
            .frame(width: size, height: size)
            .shadow(color: tint.accent.opacity(0.28), radius: size * 0.14, y: size * 0.05)
            .accessibilityHidden(true)
    }
}

/// Plain button that sinks slightly while pressed.
struct SystemSettingsClonePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.35), value: configuration.isPressed)
    }
}

/// Keyboard key glyph used in hints, such as ↩ or esc.
struct SystemSettingsCloneKeyCap: View {
    let label: String

    var body: some View {
        Text(verbatim: label)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 17)
            .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4.5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

extension Animation {
    /// Standard motion for the clone, or none under Reduce Motion.
    static func systemSettingsClone(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(duration: 0.38, bounce: 0.18)
    }
}

#if DEBUG
#Preview("Icon tiles") {
    VStack(alignment: .leading, spacing: 14) {
        ForEach(SystemSettingsDeepLinkCatalog.categories) { category in
            HStack(spacing: 10) {
                ForEach(category.panes) { pane in
                    SystemSettingsCloneIconTile(symbolName: pane.symbolName, tint: pane.tint, size: 32)
                }
            }
        }
    }
    .padding(24)
}
#endif
