import SwiftUI

/// App-wide permission controls followed by the Window Peek preferences.
///
/// Presented inside Settings > Features; every value here applies to every display.
struct PreviewsSettingsPane: View {
    let source: SettingsValueSource
    let windowAccess: WindowAccessController
    let screenCapture: ScreenCaptureAccessController
    let persistentSettingsDisabled: Bool

    private var settings: DockSettings { source.value }

    var body: some View {
        PreviewPermissionsSettingsCard(windowAccess: windowAccess, screenCapture: screenCapture)
        Group {
            SettingsCard(title: .windowPeekTitle, footnote: .windowPeekHelp) {
                SettingsToggleRow(title: .windowPeekEnabled,
                                  isOn: source.binding(\.windowPeekEnabled))
                WindowPeekPresetPicker(settings: settings) { source.apply($0) }
            }
            SettingsCard(title: .windowPeekDesignTitle) {
                SettingsPickerRow(title: .windowPeekSize,
                                  options: WindowPeekSize.settingsOptions,
                                  selection: source.binding(\.windowPeekSize))
                SettingsPickerRow(title: .windowPeekLayout,
                                  options: WindowPeekLayout.settingsOptions,
                                  selection: source.binding(\.windowPeekLayout))
                SettingsPickerRow(title: .windowPeekStyle,
                                  options: WindowPeekStyle.settingsOptions,
                                  selection: source.binding(\.windowPeekStyle))
                SettingsStackedRow(title: .windowPeekExample) {
                    WindowPeekDesignSample(size: settings.windowPeekSize, layout: settings.windowPeekLayout,
                                           style: settings.windowPeekStyle)
                }
            }
            SettingsCard(title: .windowPeekFiltersTitle) {
                SettingsToggleRow(title: .windowPeekIncludeMinimized,
                                  isOn: source.binding(\.windowPeekIncludeMinimized))
                SettingsToggleRow(title: .windowPeekIncludeUntitled,
                                  isOn: source.binding(\.windowPeekIncludeUntitled))
            }
            SettingsCard(title: .windowPeekTimingTitle) {
                SettingsSliderRow(title: .windowPeekHoverDelay, unit: .settingsSeconds,
                                  value: source.binding(\.windowPeekHoverDelay), range: 0.2...1, step: 0.1,
                                  minimumSymbol: "hare.fill", maximumSymbol: "tortoise.fill",
                                  defaultValue: DockSettings.defaults.windowPeekHoverDelay)
            }
        }
        .disabled(persistentSettingsDisabled)
    }
}

private struct WindowPeekPresetPicker: View {
    let settings: DockSettings
    let apply: (WindowPeekPreset) -> Void
    private var selected: WindowPeekPreset? { WindowPeekPreset.matching(settings) }

    var body: some View {
        SettingsStackedRow(title: .windowPeekPreset) {
            HStack(spacing: 8) {
                ForEach(WindowPeekPreset.allCases) { preset in
                    Button { apply(preset) } label: {
                        VStack(spacing: 6) {
                            Image(systemName: preset.symbol)
                                .font(.title3)
                            Text(preset.title).font(.callout.weight(.medium))
                        }
                        .frame(maxWidth: .infinity, minHeight: 58)
                    }
                    .buttonStyle(.plain)
                    .settingsSelectionCard(isSelected: selected == preset)
                    .accessibilityAddTraits(selected == preset ? [.isSelected, .isButton] : .isButton)
                }
            }
            if selected == nil {
                Text(.windowPeekPresetCustom)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private extension WindowPeekPreset {
    var symbol: String {
        switch self {
        case .compact: "list.bullet"
        case .balanced: "square.grid.2x2"
        case .showcase: "rectangle.on.rectangle"
        }
    }
}

private struct WindowPeekDesignSample: View {
    let size: WindowPeekSize
    let layout: WindowPeekLayout
    let style: WindowPeekStyle

    var body: some View {
        HStack(spacing: layout == .filmstrip ? 8 : 12) {
            sample(title: "Document")
            sample(title: "Notes")
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 12))
    }

    private func sample(title: String) -> some View {
        VStack(alignment: .leading, spacing: style == .captioned ? 7 : 4) {
            RoundedRectangle(cornerRadius: 6)
                .fill(.blue.gradient)
                .overlay { Image(systemName: "macwindow").font(.title2).foregroundStyle(.white) }
                .aspectRatio(1.6, contentMode: .fit)
            if style != .minimal { Text(verbatim: title).font(.caption).lineLimit(1) }
        }
        .padding(style == .glass ? 7 : 0)
        .background(style == .glass ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.clear),
                    in: .rect(cornerRadius: 9))
        .frame(maxWidth: size == .small ? 120 : size == .medium ? 160 : 200)
    }
}

private extension WindowPeekSize {
    static var settingsOptions: [SettingsOption<Self>] {
        [.init(value: .small, title: .windowPeekSizeSmall, symbol: "rectangle"),
         .init(value: .medium, title: .windowPeekSizeMedium, symbol: "rectangle"),
         .init(value: .large, title: .windowPeekSizeLarge, symbol: "rectangle.fill")]
    }
}

private extension WindowPeekLayout {
    static var settingsOptions: [SettingsOption<Self>] {
        [.init(value: .list, title: .windowPeekLayoutList, symbol: "list.bullet"),
         .init(value: .grid, title: .windowPeekLayoutGrid, symbol: "square.grid.2x2"),
         .init(value: .filmstrip, title: .windowPeekLayoutFilmstrip, symbol: "rectangle.on.rectangle")]
    }
}

private extension WindowPeekStyle {
    static var settingsOptions: [SettingsOption<Self>] {
        [.init(value: .glass, title: .windowPeekStyleGlass, symbol: "sparkles"),
         .init(value: .minimal, title: .windowPeekStyleMinimal, symbol: "rectangle.on.rectangle"),
         .init(value: .captioned, title: .windowPeekStyleCaptioned, symbol: "text.below.photo")]
    }
}
