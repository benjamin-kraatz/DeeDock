import SwiftUI

/// A gallery of production-rendered indicators, sized to keep every choice readable.
struct RunningIndicatorPicker: View {
    let edge: DockEdge
    @Binding var selection: DockSettings.RunningIndicatorStyle
    /// Shows the shader styles as they will actually appear once chosen.
    var animated = false
    var reduceTransparency: Bool? = nil

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
            ForEach(DockSettings.RunningIndicatorStyle.settingsOptions) { option in
                Button { selection = option.value } label: {
                    VStack(spacing: 8) {
                        RunningIndicatorThumbnail(style: option.value, edge: edge, animated: animated,
                                                  reduceTransparency: reduceTransparency)
                            .frame(height: 56)
                        Text(option.title).font(.callout.weight(.medium))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 88)
                    .padding(10)
                    .background(selection == option.value ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topTrailing) {
                        if selection == option.value {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                                .padding(6)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(option.title))
                .accessibilityAddTraits(selection == option.value ? [.isSelected] : [])
            }
        }
        .padding(14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.settingsIndicatorStyle))
    }
}

/// Deterministic artwork with native-icon-like margins, without resolving or launching an app.
private struct RunningIndicatorThumbnail: View {
    let style: DockSettings.RunningIndicatorStyle
    let edge: DockEdge
    var animated = false
    var reduceTransparency: Bool? = nil
    private let size: CGFloat = 44

    var body: some View {
        let depth = size + DockGeometry.indicatorAreaDepth
        let bounds = edge.size(length: size, depth: depth)
        let center = edge.point(CGPoint(x: size / 2, y: size / 2), depth: depth)
        let marker = edge.point(CGPoint(x: size / 2,
            y: size + DockGeometry.indicatorSpacing + DockGeometry.indicatorSize / 2), depth: depth)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 9)
                .fill(.indigo.gradient)
                .overlay {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 21)).foregroundStyle(.white)
                }
                .padding(4)
                .frame(width: size, height: size)
                .modifier(DockIconIndicator(style: style, running: true, size: size,
                                            variant: DockIndicatorVariant(identity: style.rawValue, accent: .indigo),
                                            animated: animated, reduceTransparency: reduceTransparency))
                .position(center)
            DockRunningIndicator(style: style, edge: edge).position(marker)
        }
        .frame(width: bounds.width, height: bounds.height)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Indicator gallery") {
    @Previewable @State var selection: DockSettings.RunningIndicatorStyle = .singularity
    ScrollView {
        RunningIndicatorPicker(edge: .bottom, selection: $selection, animated: true)
    }.frame(width: 540, height: 460).preferredColorScheme(.dark)
}

#Preview("Side indicators, dark and reduced transparency") {
    @Previewable @State var selection: DockSettings.RunningIndicatorStyle = .lavaChrome
    ScrollView {
        RunningIndicatorPicker(edge: .left, selection: $selection, reduceTransparency: true)
    }.frame(width: 440, height: 540).preferredColorScheme(.dark)
}
#endif
