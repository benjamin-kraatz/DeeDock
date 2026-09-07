import SwiftUI

/// The artwork inside a sidebar icon tile.
///
/// Most panes use an SF Symbol; a pane whose subject is the dock itself gets a drawn glyph,
/// which stays legible at tile size where a detailed symbol turns into a smudge.
enum SettingsGlyph: Hashable {
    case symbol(String)
    /// A display with a dock resting at its bottom edge.
    case dock
}

/// Compact symbol artwork shared by sidebar and overview rows.
struct SettingsIconTile: View {
    let glyph: SettingsGlyph
    let colors: [Color]
    var size: CGFloat = 18

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: size * 0.29, style: .continuous) }

    var body: some View {
        shape
            .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .overlay { artwork }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var artwork: some View {
        switch glyph {
        case let .symbol(name):
            Image(systemName: name)
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.22), radius: 0.5, y: 0.5)
        case .dock:
            DockTileGlyph(size: size)
        }
    }
}

/// A miniature screen with three dock icons along its bottom edge.
private struct DockTileGlyph: View {
    let size: CGFloat

    var body: some View {
        let width = size * 0.62
        let height = width * 0.72
        let dot = width * 0.14
        RoundedRectangle(cornerRadius: width * 0.16, style: .continuous)
            .strokeBorder(.white, lineWidth: max(1, size * 0.055))
            .frame(width: width, height: height)
            .overlay(alignment: .bottom) {
                HStack(spacing: dot * 0.45) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: dot * 0.3, style: .continuous)
                            .fill(.white)
                            .frame(width: dot, height: dot)
                    }
                }
                .padding(.bottom, dot * 0.5)
            }
            .shadow(color: .black.opacity(0.2), radius: 0.5, y: 0.5)
    }
}

#if DEBUG
#Preview("Icon tiles") {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(SettingsPage.dockPages) { page in
            HStack(spacing: 10) {
                SettingsIconTile(glyph: page.glyph, colors: page.tileColors)
                SettingsIconTile(glyph: page.glyph, colors: page.tileColors, size: 48)
                Text(page.title)
            }
        }
    }
    .padding()
}
#endif
