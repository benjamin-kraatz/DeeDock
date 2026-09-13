import SwiftUI

/// Where Atmosphere takes its colors from, followed only by the controls that source uses.
struct AtmosphereColorsCard: View {
    @Binding var settings: AtmosphereSettings
    let mood: AtmosphereMood
    let apply: () -> Void

    private var sources: [AtmosphereColorSource] {
        AtmosphereColorSource.allCases.filter { $0 != .mood || mood.available }
    }

    var body: some View {
        SettingsCard(title: .atmosphereSource, footnote: settings.source == .appIcon ? .atmosphereAppHelp : nil) {
            sourcePicker
            switch settings.source {
            case .manual:
                colorRow(.atmosphereFirstColor, color: \.first)
                colorRow(.atmosphereSecondColor, color: \.second)
            case .wallpaper:
                SettingsMenuRow(title: .atmosphereWallpaperMode, selection: $settings.wallpaper) {
                    ForEach(AtmosphereWallpaperMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            case .appIcon:
                EmptyView()
            case .mood:
                if mood.available { moodRows }
            }
        }
    }

    /// Segmented when every title fits; long translations fall back to a pop-up menu.
    private var sourcePicker: some View {
        ViewThatFits(in: .horizontal) {
            Picker(selection: $settings.source) { sourceItems } label: { Text(.atmosphereSource) }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                .frame(maxWidth: .infinity)
                .padding(.horizontal, SettingsMetrics.rowInset)
                .padding(.vertical, 10)
            SettingsMenuRow(title: .atmosphereSource, selection: $settings.source) { sourceItems }
        }
    }

    private var sourceItems: some View {
        ForEach(sources, id: \.self) { Text($0.title).tag($0) }
    }

    private func colorRow(_ title: LocalizedStringResource,
                          color: WritableKeyPath<AtmospherePalette, AtmosphereColor>) -> some View {
        SettingsRow(title: title) {
            ColorPicker(selection: Binding(get: { settings.manual[keyPath: color].color },
                                           set: { settings.manual[keyPath: color] = AtmosphereColor($0) }),
                        supportsOpacity: false) { Text(title) }
                .labelsHidden()
        }
    }

    @ViewBuilder private var moodRows: some View {
        let isBlank = settings.mood.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        HStack(spacing: SettingsMetrics.controlSpacing) {
            TextField(text: $settings.mood, prompt: Text(.atmosphereMoodPrompt)) { Text(.atmosphereMoodPrompt) }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .onSubmit { if !isBlank && !mood.generating { apply() } }
            AtmospherePaletteSwatches(palette: settings.moodPalette)
            if mood.generating {
                ProgressView().controlSize(.small)
            }
            Button(.atmosphereApply, action: apply)
                .disabled(mood.generating || isBlank)
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, 10)
        if mood.failed {
            SettingsInlineError(message: .atmosphereMoodError)
        }
        SettingsActionRow {
            Button(.atmosphereEditManual, systemImage: "slider.horizontal.3") {
                settings.manual = settings.moodPalette
                settings.source = .manual
            }
        }
    }
}

/// The two palette colors as small overlapping discs.
private struct AtmospherePaletteSwatches: View {
    let palette: AtmospherePalette

    var body: some View {
        HStack(spacing: -6) {
            swatch(palette.first.color)
            swatch(palette.second.color)
        }
        .accessibilityHidden(true)
    }

    private func swatch(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 20, height: 20)
            .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
    }
}

#if DEBUG
#Preview("Colors, manual") {
    @Previewable @State var settings = AtmosphereSettings()
    AtmosphereColorsCard(settings: $settings, mood: AtmosphereMood(), apply: {}).padding(24).frame(width: 620)
}
#endif
