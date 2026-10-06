import SwiftUI

/// Chooses between the full, dock-morphing Launcher and the compact grid above the Launcher tile,
/// each shown as a small schematic of the dock and the Launcher it opens.
struct LauncherStylePicker: View {
    @Binding var selection: LauncherStyle

    var body: some View {
        HStack(spacing: 8) {
            ForEach(LauncherStyle.allCases, id: \.self) { style in
                Button { selection = style } label: {
                    VStack(spacing: 8) {
                        LauncherStyleThumbnail(style: style, selected: selection == style)
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
        .accessibilityLabel(Text(.settingsLauncherStyle))
    }
}

extension LauncherStyle {
    var title: LocalizedStringResource {
        switch self {
        case .full: .settingsLauncherStyleFull
        case .compact: .settingsLauncherStyleCompact
        }
    }
}

/// A dock strip with the Launcher it opens: a wide panel grown from the dock, or a small grid
/// pointing at the Launcher tile.
private struct LauncherStyleThumbnail: View {
    let style: LauncherStyle
    let selected: Bool

    var body: some View {
        VStack(spacing: 3) {
            switch style {
            case .full:
                panel(columns: 5, rows: 2)
                    .frame(width: 86, height: 38)
            case .compact:
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        panel(columns: 3, rows: 2)
                            .frame(width: 44, height: 30)
                        Triangle()
                            .fill(.white.opacity(0.22))
                            .frame(width: 8, height: 4)
                            .padding(.leading, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: 44)
                    Spacer(minLength: 0)
                }
                .frame(width: 86, height: 38, alignment: .bottom)
            }
            dock
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.82), in: .rect(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }

    private func panel(columns: Int, rows: Int) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.white.opacity(0.22))
            .overlay {
                Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                    ForEach(0..<rows, id: \.self) { _ in
                        GridRow {
                            ForEach(0..<columns, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.7)).frame(width: 7, height: 7)
                            }
                        }
                    }
                }
            }
    }

    private var dock: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(selected ? Color.accentColor : .white.opacity(0.85))
                .frame(width: 6, height: 6)
            ForEach(0..<6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1.5).fill(.white.opacity(0.5)).frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.white.opacity(0.14), in: .capsule)
        .frame(width: 86, alignment: style == .compact ? .leading : .center)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

#if DEBUG
#Preview("Launcher style picker") {
    @Previewable @State var selection: LauncherStyle = .compact
    LauncherStylePicker(selection: $selection)
        .frame(width: 480)
        .padding()
}
#endif
