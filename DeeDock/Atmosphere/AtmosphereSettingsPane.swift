import SwiftUI
import ImagePlayground

struct AtmosphereSettingsPane: View {
    @Bindable var store: AtmosphereStore
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground
    @State private var playground = false
    @State private var decorFailed = false
    @State private var mood = AtmosphereMood()

    var body: some View {
        Form {
            Section {
                Toggle(.atmosphereEnabled, isOn: $store.settings.enabled)
                Text(.atmosphereSummary).foregroundStyle(.secondary)
                Picker(.atmospherePreset, selection: $store.settings.preset) {
                    ForEach(AtmospherePreset.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Slider(value: $store.settings.density, in: 0...1) { Text(.atmosphereDensity) }
                Slider(value: $store.settings.intensity, in: AtmosphereLimits.intensityRange) { Text(.atmosphereIntensity) }
                Toggle(.atmosphereIdle, isOn: $store.settings.idleOnly)
                Text(.atmosphereGateHelp).font(.caption).foregroundStyle(.secondary)
                Picker(.atmosphereLayout, selection: $store.settings.panorama) {
                    Text(.atmospherePerDisplay).tag(false)
                    Text(.atmospherePanorama).tag(true)
                }.pickerStyle(.radioGroup)
                Text(.atmosphereLayoutHelp).font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker(.atmosphereSource, selection: $store.settings.source) {
                    ForEach(AtmosphereColorSource.allCases.filter { $0 != .mood || mood.available }, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }.pickerStyle(.radioGroup)
                switch store.settings.source {
                case .manual:
                    ColorPicker(.atmosphereFirstColor, selection: colorBinding(first: true), supportsOpacity: false)
                    ColorPicker(.atmosphereSecondColor, selection: colorBinding(first: false), supportsOpacity: false)
                case .wallpaper:
                    Picker(.atmosphereWallpaperMode, selection: $store.settings.wallpaper) {
                        ForEach(AtmosphereWallpaperMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                case .appIcon: Text(.atmosphereAppHelp).font(.caption)
                case .mood:
                    if mood.available {
                        TextField(.atmosphereMoodPrompt, text: $store.settings.mood)
                        HStack {
                            Button(.atmosphereApply) { mood.apply(to: store) }
                                .disabled(mood.generating || store.settings.mood.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if mood.generating { ProgressView().controlSize(.small) }
                            Button(.atmosphereEditManual) {
                                store.settings.manual = store.settings.moodPalette
                                store.settings.source = .manual
                            }
                        }
                        HStack {
                            Circle().fill(store.settings.moodPalette.first.color).frame(width: 24, height: 24)
                            Circle().fill(store.settings.moodPalette.second.color).frame(width: 24, height: 24)
                        }.accessibilityHidden(true)
                        if mood.failed { Text(.atmosphereMoodError).foregroundStyle(.secondary) }
                    }
                }
            }
            if supportsImagePlayground {
                Section {
                    Button(.atmosphereGenerateDecor) { playground = true }
                    if store.decorImage != nil {
                        Button(.atmosphereRemoveDecor) { store.removeDecor() }
                    }
                    if decorFailed { Text(.atmosphereDecorError).foregroundStyle(.secondary) }
                }
            }
            Text(.atmosphereInteractionHelp).font(.caption).foregroundStyle(.secondary)
        }
        .imagePlaygroundSheet(isPresented: $playground, concepts: [.text(store.settings.mood.isEmpty ? String(localized: store.settings.preset.title) : store.settings.mood)]) { url in
            decorFailed = !store.saveDecor(from: url)
        }
        .formStyle(.grouped)
        .navigationTitle(Text(.atmosphereTitle))
        .onChange(of: store.settings.source) { _, _ in mood.cancel() }
        .onDisappear { mood.cancel() }
    }

    private func colorBinding(first: Bool) -> Binding<Color> {
        Binding(get: { first ? store.settings.manual.first.color : store.settings.manual.second.color }, set: {
            if first { store.settings.manual.first = AtmosphereColor($0) }
            else { store.settings.manual.second = AtmosphereColor($0) }
        })
    }
}

#if DEBUG
#Preview("Atmosphere") {
    AtmosphereSettingsPane(store: AtmosphereStore(defaults: nil)).frame(width: 650, height: 750)
}
#endif
