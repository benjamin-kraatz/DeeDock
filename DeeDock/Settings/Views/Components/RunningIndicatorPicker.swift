import SwiftUI

/// A gallery of production-rendered indicators, sized to keep every choice readable.
struct RunningIndicatorPicker: View {
    let edge: DockEdge
    @Binding var selection: DockSettings.RunningIndicatorStyle
    /// Shows Stardust in motion when animation is on.
    var animated = false

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
            ForEach(DockSettings.RunningIndicatorStyle.settingsOptions) { option in
                Button { selection = option.value } label: {
                    VStack(spacing: 8) {
                        RunningIndicatorThumbnail(style: option.value, edge: edge, animated: animated)
                            .frame(height: 56)
                        Text(option.title).font(.callout.weight(.medium))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 88)
                    .padding(10)
                    .settingsSelectionCard(isSelected: selection == option.value)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(option.title))
                .accessibilityAddTraits(selection == option.value ? [.isSelected] : [])
            }
        }
        .padding(SettingsMetrics.rowInset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.settingsIndicatorStyle))
    }
}

/// Deterministic artwork with native-icon-like margins, without resolving or launching an app.
private struct RunningIndicatorThumbnail: View {
    let style: DockSettings.RunningIndicatorStyle
    let edge: DockEdge
    var animated = false
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
                                            variant: DockIndicatorVariant(identity: style.rawValue),
                                            animated: animated))
                .position(center)
            DockRunningIndicator(style: style, edge: edge).position(marker)
        }
        .frame(width: bounds.width, height: bounds.height)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Indicator gallery") {
    @Previewable @State var selection: DockSettings.RunningIndicatorStyle = .stardust
    ScrollView {
        RunningIndicatorPicker(edge: .bottom, selection: $selection, animated: true)
    }.frame(width: 540, height: 460).preferredColorScheme(.dark)
}

#Preview("Side indicators, dark") {
    @Previewable @State var selection: DockSettings.RunningIndicatorStyle = .orbit
    ScrollView {
        RunningIndicatorPicker(edge: .left, selection: $selection)
    }.frame(width: 440, height: 540).preferredColorScheme(.dark)
}
#endif
