import ImagePlayground
import SwiftUI

/// App-wide Atmosphere preferences, laid out on the shared settings column.
///
/// The master switch lives in the header; every card below it is disabled while Atmosphere is off
/// so the pane reads as one feature rather than a list of unrelated controls.
struct AtmosphereSettingsPane: View {
    @Bindable var store: AtmosphereStore
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground
    @State private var playground = false
    @State private var decorFailed = false
    @State private var mood = AtmosphereMood()

    var body: some View {
        SettingsPageScaffold {
            AtmosphereHeaderCard(isOn: $store.settings.enabled)
            Group {
                SettingsCard(
                    title: .atmospherePreset,
                    footnote: store.settings.preset.hasDecor
                        ? .atmosphereInteractionHelp : nil
                ) {
                    AtmospherePresetPicker(selection: $store.settings.preset)
                    AtmosphereSliderRow(
                        title: .atmosphereDensity,
                        value: $store.settings.density,
                        range: 0...1,
                        minimumSymbol: "circle.dotted",
                        maximumSymbol: "circle.hexagongrid.fill"
                    )
                    AtmosphereSliderRow(
                        title: .atmosphereIntensity,
                        value: $store.settings.intensity,
                        range: AtmosphereLimits.intensityRange,
                        minimumSymbol: "sun.min",
                        maximumSymbol: "sun.max.fill"
                    )
                }
                AtmosphereColorsCard(
                    settings: $store.settings,
                    mood: mood,
                    apply: { mood.apply(to: store) }
                )
                SettingsCard(title: .settingsBehavior) {
                    SettingsToggleRow(
                        title: .atmosphereIdle,
                        subtitle: .atmosphereGateHelp,
                        isOn: $store.settings.idleOnly
                    )
                    SettingsMenuRow(
                        title: .atmosphereLayout,
                        subtitle: .atmosphereLayoutHelp,
                        selection: $store.settings.panorama
                    ) {
                        Text(.atmospherePerDisplay).tag(false)
                        Text(.atmospherePanorama).tag(true)
                    }
                }
                if supportsImagePlayground {
                    AtmosphereDecorCard(
                        image: store.decorImage,
                        failed: decorFailed,
                        generate: { playground = true },
                        remove: {
                            decorFailed = false
                            store.removeDecor()
                        }
                    )
                }
            }
            .disabled(!store.settings.enabled)
        }
        .imagePlaygroundSheet(
            isPresented: $playground,
            concepts: [
                .text(
                    store.settings.mood.isEmpty
                        ? String(localized: store.settings.preset.decorPrompt)
                        : String(localized: .atmosphereDecorPromptMood(mood: store.settings.mood))
                )
            ]
        ) { url in
            decorFailed = !store.saveDecor(from: url)
        }
        .navigationTitle(Text(.atmosphereTitle))
        .onChange(of: store.settings.source) { _, _ in mood.cancel() }
        .onDisappear { mood.cancel() }
    }
}

#if DEBUG
    #Preview("Atmosphere") {
        AtmosphereSettingsPane(store: AtmosphereStore(defaults: nil)).frame(
            width: 650,
            height: 750
        )
    }

    #Preview("Atmosphere, enabled, dark") {
        let store = AtmosphereStore(defaults: nil)
        store.settings.enabled = true
        store.settings.preset = .party
        store.settings.source = .wallpaper
        return AtmosphereSettingsPane(store: store)
            .frame(width: 650, height: 750)
            .preferredColorScheme(.dark)
    }
#endif
