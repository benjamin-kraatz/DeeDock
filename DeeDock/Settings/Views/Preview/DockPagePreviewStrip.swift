import SwiftUI

/// The dock sample pinned above a dock page's controls, so dragging a slider halfway down the
/// page still shows its effect.
///
/// Only pages whose controls all change the same drawing get a strip; pages with several
/// independent previews, such as Behavior, keep each one beside the controls it explains.
struct DockPagePreviewStrip: View {
    let page: SettingsPage
    /// The effective settings being edited: the shared defaults or one display's resolved values.
    let settings: DockSettings

    static func offers(_ page: SettingsPage) -> Bool { page == .appearance || page == .position }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 6) {
            sample
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(.background.secondary, in: shape)
                .overlay(shape.strokeBorder(.separator.opacity(0.4), lineWidth: 0.5))
            Text(.settingsPreviewDisclaimer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(.settingsPreview))
    }

    @ViewBuilder private var sample: some View {
        switch page {
        case .appearance:
            DockAppearancePreview(edge: settings.edge, iconSize: settings.iconSize,
                                  magnification: settings.magnification, itemSpacing: settings.itemSpacing,
                                  runningIndicatorStyle: settings.runningIndicatorStyle,
                                  appearanceSettings: settings)
        case .position:
            // Smaller than the inline diagram so the strip leaves room for the controls below it.
            DockPlacementPreview(edge: settings.edge, reference: settings.positionReference,
                                 alignment: settings.alignment, alongEdgeOffset: settings.alongEdgeOffset,
                                 edgeDistance: settings.edgeDistance, scale: 0.15)
        default:
            EmptyView()
        }
    }
}

#if DEBUG
#Preview("Appearance strip") {
    DockPagePreviewStrip(page: .appearance, settings: .defaults)
        .padding(24)
        .frame(width: 640)
}

#Preview("Position strip — left edge, dark") {
    var settings = DockSettings.defaults
    settings.edge = .left
    return DockPagePreviewStrip(page: .position, settings: settings)
        .padding(24)
        .frame(width: 640)
        .preferredColorScheme(.dark)
}
#endif
