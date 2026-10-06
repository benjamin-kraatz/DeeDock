import SwiftUI

/// Chooses between native app artwork and white line glyphs, each shown on a small dark sample.
struct DockIconStylePicker: View {
    @Binding var selection: DockIconStyle

    var body: some View {
        HStack(spacing: 8) {
            ForEach(DockIconStyle.allCases, id: \.self) { style in
                Button { selection = style } label: {
                    VStack(spacing: 8) {
                        DockIconStyleThumbnail(style: style)
                            .frame(height: 56)
                        Text(style.title).font(.callout.weight(.medium))
                    }
                    .frame(maxWidth: .infinity, minHeight: 88)
                    .padding(10)
                    .settingsSelectionCard(isSelected: selection == style)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(style.title))
                .accessibilityAddTraits(selection == style ? [.isSelected] : [])
            }
        }
        .padding(SettingsMetrics.rowInset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.settingsIconStyle))
    }
}

extension DockIconStyle {
    var title: LocalizedStringResource {
        switch self {
        case .native: .settingsIconStyleNative
        case .line: .settingsIconStyleLine
        }
    }
}

/// Three sample tiles on dark glass. The Line sample draws real catalog glyphs, and its middle
/// tile glows as if hovered.
private struct DockIconStyleThumbnail: View {
    let style: DockIconStyle
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let size: CGFloat = 34
    private struct Sample {
        let symbol: String
        let color: Color
        /// The catalog glyph: a DOKK tile, or an app's bundle identifier and `.app` name.
        let source: Source

        enum Source {
            case tile(LineIconTile)
            case app(bundleIdentifier: String, name: String)
        }

        var glyph: LineIconGlyph? {
            switch source {
            case .tile(let tile): LineIconCatalog.shared.glyph(for: tile)
            case .app(let identifier, let name):
                LineIconCatalog.shared.glyph(bundleIdentifier: identifier,
                                             url: URL(fileURLWithPath: "/Applications/\(name).app"))
            }
        }
    }

    private static let samples = [
        Sample(symbol: "safari", color: .blue, source: .app(bundleIdentifier: "com.apple.Safari", name: "Safari")),
        Sample(symbol: "message.fill", color: .green, source: .app(bundleIdentifier: "com.apple.MobileSMS", name: "Messages")),
        Sample(symbol: "trash", color: .gray, source: .tile(.trash)),
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.samples.indices, id: \.self) { index in
                let sample = Self.samples[index]
                if style == .line, let glyph = sample.glyph {
                    DockLineIconArtwork(icon: DockLineIcon(glyph: glyph), size: size, hovered: index == 1,
                                        reduceMotion: true, reduceTransparency: reduceTransparency)
                } else {
                    RoundedRectangle(cornerRadius: size * 0.22)
                        .fill(sample.color.gradient)
                        .overlay {
                            Image(systemName: sample.symbol)
                                .font(.system(size: size * 0.42, weight: .medium)).foregroundStyle(.white)
                        }
                        .padding(size * 0.08)
                        .frame(width: size, height: size)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.82), in: .capsule)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Icon style picker") {
    @Previewable @State var selection: DockIconStyle = .line
    DockIconStylePicker(selection: $selection)
        .frame(width: 480)
        .padding()
}
#endif
