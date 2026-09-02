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

/// A rounded, gradient app-style tile, the size and finish macOS sidebars use.
struct SettingsIconTile: View {
    let glyph: SettingsGlyph
    let colors: [Color]
    var size: CGFloat = 24

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: size * 0.29, style: .continuous) }

    var body: some View {
        shape
            .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            // A short gloss and a hairline rim give the tile depth without a drop shadow.
            .overlay {
                shape.fill(LinearGradient(colors: [.white.opacity(0.32), .clear],
                                          startPoint: .top, endPoint: .center))
            }
            .overlay { shape.strokeBorder(.white.opacity(0.3), lineWidth: 0.5) }
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
        ForEach(SettingsCategory.allCases) { category in
            HStack(spacing: 10) {
                SettingsIconTile(glyph: category.glyph, colors: category.tileColors)
                SettingsIconTile(glyph: category.glyph, colors: category.tileColors, size: 48)
                Text(category.title)
            }
        }
    }
    .padding()
}
#endif
